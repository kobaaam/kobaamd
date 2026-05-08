import Foundation
import Observation

@Observable
@MainActor
final class BacklinksViewModel {
    var linked: [Backlink] = []
    var unlinked: [Backlink] = []
    var isLoading: Bool = false
    var hasAnthropicKey: Bool = false
    weak var appViewModel: AppViewModel?

    private let checker: BacklinkContextCheckerProtocol
    private let cache: BacklinkContextCache
    private var refreshTask: Task<Void, Never>? = nil
    private var currentTargetURL: URL? = nil

    init(
        checker: BacklinkContextCheckerProtocol = BacklinkContextChecker(),
        cache: BacklinkContextCache = BacklinkContextCache()
    ) {
        self.checker = checker
        self.cache = cache
    }

    func refresh(currentURL: URL?, workspaceFolders: [URL]) {
        refreshTask?.cancel()
        isLoading = true

        let checker = self.checker
        let cache = self.cache
        let hasKey = {
            guard let key = APIKeyStore.load(for: .anthropic) else { return false }
            return !key.isEmpty
        }()
        currentTargetURL = currentURL
        hasAnthropicKey = hasKey

        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            guard let targetURL = currentURL else {
                await MainActor.run {
                    guard let self else { return }
                    self.linked = []
                    self.unlinked = []
                    self.isLoading = false
                }
                return
            }

            let result = await Task.detached(priority: .userInitiated) {
                await Self.scanWorkspace(
                    targetURL: targetURL,
                    workspaceFolders: workspaceFolders,
                    hasAnthropicKey: hasKey,
                    checker: checker,
                    cache: cache
                )
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.linked = result.linked
                self.unlinked = result.unlinked
                self.isLoading = false
            }
        }
    }

    func convertToLink(_ backlink: Backlink) async {
        guard let targetURL = currentTargetURL else { return }

        do {
            let original = try await Task.detached(priority: .userInitiated) {
                try FileService().readFile(at: backlink.sourceURL)
            }.value

            let updated = BacklinksScanner.convertToLink(
                sourceContent: original,
                range: backlink.matchRange,
                targetURL: targetURL
            )

            try await Task.detached(priority: .userInitiated) {
                try FileService().saveFile(at: backlink.sourceURL, content: updated)
            }.value

            appViewModel?.syncTabContent(url: backlink.sourceURL, updated: updated)
            unlinked.removeAll { $0.id == backlink.id }
        } catch {
            return
        }
    }

    private static func scanWorkspace(
        targetURL: URL,
        workspaceFolders: [URL],
        hasAnthropicKey: Bool,
        checker: BacklinkContextCheckerProtocol,
        cache: BacklinkContextCache
    ) async -> (linked: [Backlink], unlinked: [Backlink]) {
        struct UnlinkedCandidate: Sendable {
            let backlink: Backlink
            let sourceContent: String
        }

        let fileManager = FileManager.default
        let targetBasename = targetURL.deletingPathExtension().lastPathComponent
        var linkedResults: [Backlink] = []
        var unlinkedCandidates: [UnlinkedCandidate] = []

        for folder in workspaceFolders {
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            // 直接 enumerator を for-in すると Swift 6 で makeIterator が
            // async コンテキスト不可になる警告が出るため、compactMap で snapshot にする
            let allURLs = enumerator.compactMap { $0 as? URL }
            for fileURL in allURLs {
                guard fileURL != targetURL else { continue }
                guard FileService.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

                guard let content = try? FileService().readFile(at: fileURL) else { continue }
                let result = BacklinksScanner.scan(
                    sourceURL: fileURL,
                    sourceContent: content,
                    targetURL: targetURL
                )

                linkedResults.append(contentsOf: result.linked)
                if hasAnthropicKey {
                    unlinkedCandidates.append(contentsOf: result.unlinked.map {
                        UnlinkedCandidate(backlink: $0, sourceContent: content)
                    })
                }
            }
        }

        linkedResults.sort(by: backlinksSort)

        guard hasAnthropicKey, !targetBasename.isEmpty else {
            return (linkedResults, [])
        }

        var acceptedUnlinked: [Backlink] = []
        var didMutateCache = false

        for candidate in unlinkedCandidates.prefix(10) {
            let sourceHash = BacklinkContextCache.hash(of: candidate.sourceContent)
            let matchOffset = candidate.backlink.matchRange.location

            let verdict: BacklinkContextCache.Verdict?
            if let cached = cache.get(sourceHash: sourceHash, targetBasename: targetBasename, matchOffset: matchOffset) {
                verdict = cached
            } else {
                let snippet = markedSnippet(for: candidate.backlink)
                let judged = await checker.judge(
                    sourceContent: candidate.sourceContent,
                    snippet: snippet,
                    targetBasename: targetBasename
                )
                verdict = judged
                if let judged {
                    cache.put(
                        sourceHash: sourceHash,
                        targetBasename: targetBasename,
                        matchOffset: matchOffset,
                        verdict: judged
                    )
                    didMutateCache = true
                }
            }

            if verdict == .yes {
                acceptedUnlinked.append(candidate.backlink)
            }
        }

        if didMutateCache {
            cache.save()
        }

        acceptedUnlinked.sort(by: backlinksSort)
        return (linkedResults, acceptedUnlinked)
    }

    private static func markedSnippet(for backlink: Backlink) -> String {
        guard !backlink.matchedText.isEmpty,
              let range = backlink.snippet.range(of: backlink.matchedText) else {
            return backlink.snippet
        }

        var marked = backlink.snippet
        marked.replaceSubrange(range, with: "<<<\(backlink.matchedText)>>>")
        return marked
    }

    private static func backlinksSort(lhs: Backlink, rhs: Backlink) -> Bool {
        if lhs.sourceURL.path != rhs.sourceURL.path {
            return lhs.sourceURL.path.localizedCaseInsensitiveCompare(rhs.sourceURL.path) == .orderedAscending
        }
        return lhs.matchRange.location < rhs.matchRange.location
    }
}
