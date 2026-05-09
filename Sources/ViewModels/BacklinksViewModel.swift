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

    // ワークスペース内ファイル一覧のキャッシュ。folder set が変わらない限り再列挙を抑止する。
    // FileManager.enumerator は 9000 ファイル規模で 1.5 秒以上かかるためファイル切替の度に走らせない。
    @ObservationIgnored
    private static var fileListCache: (folderKey: String, urls: [URL])? = nil
    @ObservationIgnored
    private static let fileListCacheLock = NSLock()

    init(
        checker: BacklinkContextCheckerProtocol = BacklinkContextChecker(),
        cache: BacklinkContextCache = BacklinkContextCache()
    ) {
        self.checker = checker
        self.cache = cache
    }

    func refresh(currentURL: URL?, workspaceFolders: [URL]) {
        PerfLogger.event("Backlinks.refresh", "url=\(currentURL?.lastPathComponent ?? "nil") folders=\(workspaceFolders.count)")
        refreshTask?.cancel()
        // isLoading は 200ms 以上かかる場合のみ立てる（短時間完了の flash を抑止）。
        // ファイル切替直後の "loading" 体感を消すためのキー変更。
        let loadingFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.isLoading = true
            }
        }

        let checker = self.checker
        let cache = self.cache
        PerfLogger.begin("Backlinks.APIKeyStore.load")
        let hasKey = {
            guard let key = APIKeyStore.load(for: .anthropic) else { return false }
            return !key.isEmpty
        }()
        PerfLogger.end("Backlinks.APIKeyStore.load")
        currentTargetURL = currentURL
        hasAnthropicKey = hasKey

        refreshTask = Task { [weak self] in
            // 800ms 待機: ファイル切替直後はエディタ・プレビューのスクロール／編集体験を優先。
            // この間に他の操作で再度 refresh が走れば cancel されるので無駄な scan も抑制される。
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else {
                loadingFlashTask.cancel()
                return
            }

            guard let targetURL = currentURL else {
                loadingFlashTask.cancel()
                await MainActor.run {
                    guard let self else { return }
                    self.linked = []
                    self.unlinked = []
                    self.isLoading = false
                }
                return
            }

            PerfLogger.begin("Backlinks.scanWorkspace")
            // .utility priority: ユーザー操作（スクロール / 編集）を優先するため低めに。
            let result = await Task.detached(priority: .utility) {
                await Self.scanWorkspace(
                    targetURL: targetURL,
                    workspaceFolders: workspaceFolders,
                    hasAnthropicKey: hasKey,
                    checker: checker,
                    cache: cache
                )
            }.value
            PerfLogger.end("Backlinks.scanWorkspace")

            guard !Task.isCancelled else {
                loadingFlashTask.cancel()
                return
            }
            loadingFlashTask.cancel()
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
        struct FileScanResult: Sendable {
            let linked: [Backlink]
            let unlinked: [UnlinkedCandidate]
        }

        let fileManager = FileManager.default
        let targetBasename = targetURL.deletingPathExtension().lastPathComponent
        var linkedResults: [Backlink] = []
        var unlinkedCandidates: [UnlinkedCandidate] = []

        // ファイル一覧キャッシュ: folder set のキー（path 連結）が一致すれば前回の列挙結果を再利用。
        // 9000 ファイル超のワークスペースで FileManager.enumerator が 1.5s 以上かかる問題を回避。
        let folderKey = workspaceFolders.map { $0.path }.sorted().joined(separator: "\n")
        let cachedURLs: [URL]? = fileListCacheLock.withLock {
            if let cache = fileListCache, cache.folderKey == folderKey {
                return cache.urls
            }
            return nil
        }

        var allFileURLs: [URL]
        if let cachedURLs {
            PerfLogger.event("Backlinks.scanWorkspace.fileList", "source=cache count=\(cachedURLs.count)")
            allFileURLs = cachedURLs.filter { $0 != targetURL }
        } else {
            PerfLogger.begin("Backlinks.scanWorkspace.enumerate")
            var collected: [URL] = []
            for folder in workspaceFolders {
                // includingPropertiesForKeys: nil で attribute prefetch を抑止。
                // .isRegularFileKey の prefetch は inode 読み込みを発生させ 9000 ファイルで 1s 超かかる。
                guard let enumerator = fileManager.enumerator(
                    at: folder,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continue
                }
                while let fileURL = enumerator.nextObject() as? URL {
                    guard FileService.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                    collected.append(fileURL)
                }
            }
            PerfLogger.end("Backlinks.scanWorkspace.enumerate")

            fileListCacheLock.withLock {
                fileListCache = (folderKey: folderKey, urls: collected)
            }

            PerfLogger.event("Backlinks.scanWorkspace.fileList", "source=fresh count=\(collected.count)")
            allFileURLs = collected.filter { $0 != targetURL }
        }

        PerfLogger.event("Backlinks.scanWorkspace.files", "count=\(allFileURLs.count)")

        // 並列 file read + scan（最大 8 並列に制限してリソース消費を抑える）
        let perFileResults: [FileScanResult] = await withTaskGroup(of: FileScanResult?.self) { group in
            let parallelism = min(8, max(1, allFileURLs.count))
            var iterator = allFileURLs.makeIterator()

            // 初期に parallelism 個タスク起動
            for _ in 0..<parallelism {
                guard let fileURL = iterator.next() else { break }
                group.addTask {
                    guard let content = try? FileService().readFile(at: fileURL) else { return nil }
                    let scan = BacklinksScanner.scan(
                        sourceURL: fileURL,
                        sourceContent: content,
                        targetURL: targetURL
                    )
                    return FileScanResult(
                        linked: scan.linked,
                        unlinked: hasAnthropicKey
                            ? scan.unlinked.map { UnlinkedCandidate(backlink: $0, sourceContent: content) }
                            : []
                    )
                }
            }

            // 完了を 1 件受けたら次を投入する drain
            var collected: [FileScanResult] = []
            while let result = await group.next() {
                if let result {
                    collected.append(result)
                }
                if let fileURL = iterator.next() {
                    group.addTask {
                        guard let content = try? FileService().readFile(at: fileURL) else { return nil }
                        let scan = BacklinksScanner.scan(
                            sourceURL: fileURL,
                            sourceContent: content,
                            targetURL: targetURL
                        )
                        return FileScanResult(
                            linked: scan.linked,
                            unlinked: hasAnthropicKey
                                ? scan.unlinked.map { UnlinkedCandidate(backlink: $0, sourceContent: content) }
                                : []
                        )
                    }
                }
            }
            return collected
        }

        for r in perFileResults {
            linkedResults.append(contentsOf: r.linked)
            unlinkedCandidates.append(contentsOf: r.unlinked)
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
