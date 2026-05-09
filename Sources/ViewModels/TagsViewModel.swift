import Foundation
import Observation

struct TagItem: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
}

struct TaggedFile: Identifiable, Equatable {
    let id: String
    let url: URL
    let fileName: String
}

enum TagSortMode: String, CaseIterable, Identifiable {
    case alphabetical
    case count

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical:
            return "A→Z"
        case .count:
            return "件数"
        }
    }
}

@Observable
@MainActor
final class TagsViewModel {
    var tags: [TagItem] = []
    var selectedTag: String? = nil
    var taggedFiles: [TaggedFile] = []
    var isScanning: Bool = false
    var sortMode: TagSortMode = .alphabetical {
        didSet { applySort() }
    }

    private var tagToFiles: [String: Set<URL>] = [:]
    private var workspaceRoots: [URL] = []
    private var scanTask: Task<Void, Never>? = nil

    func updateWorkspaceRoots(_ urls: [URL]) {
        workspaceRoots = urls
        refresh()
    }

    func updateFile(_ url: URL, text: String) {
        for key in Array(tagToFiles.keys) {
            tagToFiles[key]?.remove(url)
            if tagToFiles[key]?.isEmpty == true {
                tagToFiles.removeValue(forKey: key)
            }
        }

        let newTags = Self.extractTags(from: text)
        for tag in newTags {
            tagToFiles[tag, default: []].insert(url)
        }

        rebuildTagList()
        rebuildSelectedFiles()
    }

    func selectTag(_ name: String) {
        if selectedTag == name {
            selectedTag = nil
        } else {
            selectedTag = name
        }
        rebuildSelectedFiles()
    }

    func refresh() {
        scanTask?.cancel()
        guard !workspaceRoots.isEmpty else {
            tagToFiles = [:]
            tags = []
            taggedFiles = []
            isScanning = false
            return
        }

        isScanning = true
        let roots = workspaceRoots
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let scanned = await Self.scanWorkspace(folders: roots)
            guard !Task.isCancelled, let self else { return }
            self.tagToFiles = scanned
            self.rebuildTagList()
            self.rebuildSelectedFiles()
            self.isScanning = false
        }
    }

    private func rebuildTagList() {
        tags = tagToFiles.map { TagItem(id: $0.key, name: $0.key, count: $0.value.count) }
        applySort()
    }

    private func applySort() {
        switch sortMode {
        case .alphabetical:
            tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .count:
            tags.sort {
                if $0.count == $1.count {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.count > $1.count
            }
        }
    }

    private func rebuildSelectedFiles() {
        guard let selected = selectedTag, let urls = tagToFiles[selected] else {
            taggedFiles = []
            return
        }

        taggedFiles = urls
            .map { TaggedFile(id: $0.path, url: $0, fileName: $0.lastPathComponent) }
            .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    nonisolated static func scanWorkspace(folders: [URL], maxDepth: Int = 5) async -> [String: Set<URL>] {
        await Task.detached(priority: .userInitiated) {
            var result: [String: Set<URL>] = [:]
            for folder in folders {
                if let collected = try? collect(in: folder, maxDepth: maxDepth) {
                    for (tag, urls) in collected {
                        result[tag, default: []].formUnion(urls)
                    }
                }
            }
            return result
        }.value
    }

    nonisolated private static func collect(in root: URL, maxDepth: Int) throws -> [String: Set<URL>] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        let rootDepth = root.pathComponents.count
        var result: [String: Set<URL>] = [:]
        var processed = 0

        for case let url as URL in enumerator {
            processed += 1
            if processed % 50 == 0 {
                try Task.checkCancellation()
            }

            let depth = url.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let tags = extractTags(from: content)
            for tag in tags {
                result[tag, default: []].insert(url)
            }
        }
        return result
    }

    nonisolated static func extractTags(from text: String) -> Set<String> {
        var result: Set<String> = []
        let (frontmatter, body) = splitFrontmatter(text)
        if let fm = frontmatter {
            result.formUnion(parseFrontmatterTags(fm))
        }
        result.formUnion(parseInlineTags(body))
        return result
    }

    nonisolated private static func splitFrontmatter(_ text: String) -> (String?, String) {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, text)
        }

        var endIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard let end = endIndex else { return (nil, text) }
        let fmContent = lines[1..<end].joined(separator: "\n")
        let bodyContent = end + 1 < lines.count ? lines[(end + 1)...].joined(separator: "\n") : ""
        return (fmContent, bodyContent)
    }

    nonisolated private static func parseFrontmatterTags(_ fm: String) -> Set<String> {
        var result: Set<String> = []
        let lines = fm.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: #"^tags?\s*:\s*"#, options: .regularExpression) {
                let rest = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    var j = i + 1
                    while j < lines.count {
                        let nextTrim = lines[j].trimmingCharacters(in: .whitespaces)
                        if nextTrim.hasPrefix("- ") {
                            let value = String(nextTrim.dropFirst(2))
                                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                            if !value.isEmpty {
                                result.insert(normalizeTag(value))
                            }
                            j += 1
                        } else if nextTrim.isEmpty {
                            j += 1
                        } else {
                            break
                        }
                    }
                    i = j
                    continue
                } else if rest.hasPrefix("[") && rest.hasSuffix("]") {
                    let inner = String(rest.dropFirst().dropLast())
                    let parts = inner.split(separator: ",")
                        .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
                    for part in parts where !part.isEmpty {
                        result.insert(normalizeTag(part))
                    }
                } else {
                    let parts = rest.split(separator: ",")
                        .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
                    for part in parts where !part.isEmpty {
                        result.insert(normalizeTag(part))
                    }
                }
            }
            i += 1
        }

        return result
    }

    nonisolated private static func parseInlineTags(_ body: String) -> Set<String> {
        var result: Set<String> = []
        var inFence = false
        let lines = body.components(separatedBy: "\n")
        let pattern = #"(?<![\w/])#([\p{L}0-9_][\p{L}0-9_\-/]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            let scanLine: String = {
                if let match = line.range(of: #"^\s*#{1,6}\s"#, options: .regularExpression) {
                    return String(line[match.upperBound...])
                }
                return line
            }()

            let nsLine = scanLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            regex.enumerateMatches(in: scanLine, range: range) { match, _, _ in
                guard let match, match.numberOfRanges >= 2 else { return }
                let name = nsLine.substring(with: match.range(at: 1))
                if !name.isEmpty {
                    result.insert(normalizeTag(name))
                }
            }
        }

        return result
    }

    nonisolated private static func normalizeTag(_ raw: String) -> String {
        var value = raw
        if value.hasPrefix("#") {
            value = String(value.dropFirst())
        }
        return value
    }
}
