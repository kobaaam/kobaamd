import Foundation
import Observation

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    let label: String
    let text: String
    let line: Int
    let fileURL: URL?

    init(id: UUID = UUID(), label: String, text: String, line: Int, fileURL: URL? = nil) {
        self.id = id
        self.label = label
        self.text = text
        self.line = line
        self.fileURL = fileURL
    }
}

enum TodoScope: String, CaseIterable, Identifiable {
    case file
    case folder
    case workspace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .file:
            return "File"
        case .folder:
            return "Folder"
        case .workspace:
            return "Workspace"
        }
    }
}

@Observable
@MainActor
final class TodoViewModel {
    var items: [TodoItem] = []
    var scope: TodoScope = .file
    /// Folder/Workspace スキャン進行中フラグ（プログレス UI 用）
    var isScanning: Bool = false

    // File スコープ用 — 現状の編集中テキスト
    private var lastEditorText: String = ""
    // Folder スコープ用 — 選択中のディレクトリ（ファイル選択時はその親ディレクトリを使う）
    private var folderRoot: URL? = nil
    // Workspace スコープ用 — 開いているワークスペースフォルダ群
    private var workspaceRoots: [URL] = []

    private var debounceTask: Task<Void, Never>? = nil
    private var scanTask: Task<Void, Never>? = nil

    // MARK: - File scope

    /// 編集中ファイルのテキスト変更で呼ばれる。File スコープ時のみ即時反映、それ以外は記録のみ。
    func update(text: String) {
        lastEditorText = text
        guard scope == .file else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let extracted = await Task.detached(priority: .userInitiated) {
                Self.parseTodos(from: text, fileURL: nil)
            }.value
            guard !Task.isCancelled else { return }
            self.items = extracted
        }
    }

    // テスト用（デバウンスなし、File スコープ）
    func extractTodos(from text: String) async -> [TodoItem] {
        await Task.detached(priority: .userInitiated) {
            Self.parseTodos(from: text, fileURL: nil)
        }.value
    }

    // MARK: - Scope switching

    func setScope(_ newScope: TodoScope) {
        guard newScope != scope else { return }
        scope = newScope
        refresh()
    }

    /// 外部から呼ばれる: 選択中ディレクトリ更新（Folder スコープに反映）
    func updateFolderRoot(_ url: URL?) {
        folderRoot = url
        if scope == .folder { refresh() }
    }

    /// 外部から呼ばれる: ワークスペースフォルダ更新（Workspace スコープに反映）
    func updateWorkspaceRoots(_ urls: [URL]) {
        workspaceRoots = urls
        if scope == .workspace { refresh() }
    }

    /// 現在のスコープに応じた再収集をトリガする。
    func refresh() {
        switch scope {
        case .file:
            debounceTask?.cancel()
            scanTask?.cancel()
            isScanning = false
            let text = lastEditorText
            Task { [weak self] in
                let extracted = await Task.detached(priority: .userInitiated) {
                    Self.parseTodos(from: text, fileURL: nil)
                }.value
                guard let self else { return }
                self.items = extracted
            }
        case .folder:
            scheduleScan { [folderRoot] in
                guard let folderRoot else { return [] }
                return await Self.scanDirectory(at: folderRoot)
            }
        case .workspace:
            scheduleScan { [workspaceRoots] in
                await Self.scanWorkspace(folders: workspaceRoots)
            }
        }
    }

    private func scheduleScan(_ work: @escaping () async -> [TodoItem]) {
        debounceTask?.cancel()
        scanTask?.cancel()
        isScanning = true
        // 即時クリアはせず、500ms デバウンス後に新結果で置き換える（チラツキ低減）
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            let result = await work()
            guard !Task.isCancelled else { return }
            self.items = result
            self.isScanning = false
        }
    }

    // MARK: - Directory / Workspace scan

    /// 指定ディレクトリ配下の `.md` ファイルから TODO を収集する。
    /// maxDepth=5 (FileService.loadNodes と同一)
    nonisolated static func scanDirectory(at root: URL, maxDepth: Int = 5) async -> [TodoItem] {
        await Task.detached(priority: .userInitiated) {
            collectTodos(in: root, maxDepth: maxDepth)
        }.value
    }

    /// 複数フォルダを横断して TODO を収集する。
    nonisolated static func scanWorkspace(folders: [URL], maxDepth: Int = 5) async -> [TodoItem] {
        await Task.detached(priority: .userInitiated) {
            var results: [TodoItem] = []
            for folder in folders {
                results.append(contentsOf: collectTodos(in: folder, maxDepth: maxDepth))
            }
            return results
        }.value
    }

    nonisolated private static func collectTodos(in root: URL, maxDepth: Int) -> [TodoItem] {
        let fm = FileManager.default
        var results: [TodoItem] = []
        let rootDepth = root.pathComponents.count
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            results.append(contentsOf: parseTodos(from: content, fileURL: url))
        }
        return results
    }

    // MARK: - Parser (既存ロジック踏襲、fileURL 引数追加)

    nonisolated private static func parseTodos(from text: String, fileURL: URL?) -> [TodoItem] {
        let lines = text.components(separatedBy: .newlines)
        var results: [TodoItem] = []
        results.reserveCapacity(min(lines.count, 64))

        let pattern = #"(?:<!--\s*)?(TODO|FIXME)\s*:\s*(.+?)(?:\s*-->)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        for (index, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            let label = nsLine.substring(with: match.range(at: 1)).uppercased()
            let todoText = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            results.append(
                TodoItem(
                    id: UUID(),
                    label: label,
                    text: todoText,
                    line: index + 1,
                    fileURL: fileURL
                )
            )
        }
        return results
    }
}
