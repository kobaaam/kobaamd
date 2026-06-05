import Foundation
import Observation

// MARK: - QuickOpenViewModel

@Observable
@MainActor
final class QuickOpenViewModel {
    var query: String = ""
    var candidates: [QuickOpenItem] = []
    var selectedIndex: Int = 0

    struct QuickOpenItem: Identifiable {
        let id: URL
        let fileName: String
        let relativePath: String
        let url: URL
    }

    private var allItems: [QuickOpenItem] = []
    /// E1 active session ルート（KMD-229）。nil なら folders 全体。
    private(set) var scopedRootURL: URL?

    // MARK: - Indexing

    /// FileTreeViewModel の folders からファイルノードをフラット化してインデックス化する。
    /// ディレクトリは除外し、最大 500 件でキャップ。
    func indexFiles(from folders: [WorkspaceFolder], scopedTo root: URL? = nil) {
        scopedRootURL = root?.standardizedFileURL
        let scopePath = scopedRootURL?.path
        var items: [QuickOpenItem] = []
        for folder in folders {
            if let scopePath {
                let folderPath = folder.url.standardizedFileURL.path
                guard folderPath == scopePath || folderPath.hasPrefix(scopePath + "/") else { continue }
            }
            flatten(nodes: folder.nodes, folderURL: folder.url, scopePath: scopePath, into: &items)
            if items.count >= 500 { break }
        }
        allItems = Array(items.prefix(500))
    }

    private func flatten(
        nodes: [FileNode],
        folderURL: URL,
        scopePath: String?,
        into items: inout [QuickOpenItem]
    ) {
        for node in nodes {
            if node.isDirectory {
                if let children = node.children {
                    flatten(nodes: children, folderURL: folderURL, scopePath: scopePath, into: &items)
                }
            } else {
                let std = node.url.standardizedFileURL
                if let scopePath, !std.path.hasPrefix(scopePath) { continue }
                let relativePath = std.path
                    .replacingOccurrences(of: folderURL.path + "/", with: "")
                items.append(QuickOpenItem(
                    id: std,
                    fileName: node.name,
                    relativePath: relativePath,
                    url: std
                ))
            }
            if items.count >= 500 { return }
        }
    }

    func isWithinScope(_ url: URL) -> Bool {
        guard let root = scopedRootURL else { return true }
        let path = url.standardizedFileURL.path
        return path == root.path || path.hasPrefix(root.path + "/")
    }

    // MARK: - Filtering

    /// query に基づいて candidates を更新する。
    /// query が空なら全件（最大 20 件）、空でなければ fileName で contains マッチ（大文字小文字無視）。
    func filter() {
        if query.isEmpty {
            candidates = Array(allItems.prefix(20))
        } else {
            candidates = allItems
                .filter { $0.fileName.localizedCaseInsensitiveContains(query) }
                .prefix(20)
                .map { $0 }
        }
        selectedIndex = 0
    }

    // MARK: - Selection

    func selectNext() {
        guard !candidates.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, candidates.count - 1)
    }

    func selectPrev() {
        guard !candidates.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    var selectedItem: QuickOpenItem? {
        guard selectedIndex < candidates.count else { return nil }
        return candidates[selectedIndex]
    }
}
