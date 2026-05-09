import Foundation

enum MCPToolSupport {
    static let markdownExtensions: Set<String> = ["md", "markdown"]

    struct NoteSummary: Sendable {
        let title: String
        let frontmatterText: String?
        let body: String
        let bodyStartLine: Int
    }

    struct Heading: Sendable {
        let level: Int
        let text: String
        let line: Int
    }

    static func textContent(_ text: String) -> JSONValue {
        .object([
            "type": .string("text"),
            "text": .string(text)
        ])
    }

    static func parseArguments(_ args: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let object) = args else {
            throw MCPToolError.invalidArguments("Arguments must be an object")
        }
        return object
    }

    static func requiredString(_ key: String, from object: [String: JSONValue]) throws -> String {
        guard let value = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw MCPToolError.invalidArguments("Invalid params: missing \(key)")
        }
        return value
    }

    static func optionalString(_ key: String, from object: [String: JSONValue]) -> String? {
        object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optionalInt(_ key: String, from object: [String: JSONValue]) -> Int? {
        object[key]?.intValue
    }

    static func listMarkdownFiles(in root: URL, under subpath: String? = nil) throws -> [URL] {
        let baseURL: URL
        if let subpath, !subpath.isEmpty {
            baseURL = try VaultPath(vaultRoot: root).resolve(subpath)
        } else {
            baseURL = root
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: baseURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MCPToolError.invalidArguments("Invalid params: path is not a directory")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let vaultPath = VaultPath(vaultRoot: root)
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            // Skip symlinks to avoid traversal outside vault
            guard values?.isSymbolicLink != true else { continue }
            guard values?.isRegularFile == true else { continue }
            // Re-validate each path through VaultPath
            guard (try? vaultPath.resolve(fileURL.path)) != nil else { continue }
            guard markdownExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            files.append(fileURL)
        }

        return files.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    static func relativePath(for fileURL: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path

        if path == rootPath {
            return "."
        }

        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }

        return fileURL.lastPathComponent
    }

    static func loadNote(at fileURL: URL) throws -> NoteSummary {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let split = Frontmatter.split(text: content)
        let bodyStartLine: Int

        if let frontmatterText = split.frontmatterText {
            bodyStartLine = frontmatterText.components(separatedBy: "\n").count + 3
        } else {
            bodyStartLine = 1
        }

        let title = extractTitle(from: split.frontmatterText, body: split.body, fallback: fileURL.deletingPathExtension().lastPathComponent)
        return NoteSummary(title: title, frontmatterText: split.frontmatterText, body: split.body, bodyStartLine: bodyStartLine)
    }

    static func extractTitle(from frontmatterText: String?, body: String, fallback: String) -> String {
        if let frontmatterText {
            let frontmatter = Frontmatter.parse(yaml: frontmatterText)
            if let title = frontmatter.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
        }

        if let heading = extractHeadings(from: body, lineOffset: 0).first?.text, !heading.isEmpty {
            return heading
        }

        return fallback
    }

    static func extractHeadings(from body: String, lineOffset: Int) -> [Heading] {
        let lines = body.components(separatedBy: .newlines)
        var headings: [Heading] = []
        headings.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            guard line.first == "#" else { continue }

            let level = line.prefix { $0 == "#" }.count
            guard (1...6).contains(level) else { continue }

            let markerEnd = line.index(line.startIndex, offsetBy: level)
            guard markerEnd < line.endIndex, line[markerEnd] == " " else { continue }

            let textStart = line.index(after: markerEnd)
            let headingText = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
            headings.append(Heading(level: level, text: headingText, line: index + 1 + lineOffset))
        }

        return headings
    }

    static func makeSnippet(from line: String, maxLength: Int = 100) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }

        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<end]) + "..."
    }

    static func encodeJSONString(_ value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MCPToolError.invalidArguments("Failed to encode JSON")
        }
        return string
    }
}
