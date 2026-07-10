import Testing
@testable import kobaamd
import Foundation

// FileTreeViewModel のユニットテスト。
// saveWorkspace() 内の Security-Scoped Bookmark は sandbox 外では nil になり
// compactMap で除外されるだけで例外は発生しない。
// reloadFolder() は AppState.shared の showHiddenFiles / indexDependencyDirectories を
// 参照するが、どちらもデフォルト false で問題ない。
@Suite("FileTreeViewModel")
@MainActor
struct FileTreeViewModelTests {
    let workspace: TempWorkspace
    let vm: FileTreeViewModel

    init() throws {
        workspace = try TempWorkspace()
        vm = FileTreeViewModel()
    }

    // MARK: - addFolder

    @Test("addFolder で WorkspaceFolder が追加される")
    func addFolderAppendsEntry() async throws {
        let dir = workspace.root
        vm.addFolder(url: dir)
        #expect(vm.folders.count == 1)
        #expect(vm.folders[0].url == dir)
    }

    @Test("addFolder 後に reloadFolder が完了してノードが取得できる")
    func addFolderBuildsNodeTree() async throws {
        try workspace.write("hello.md", to: "hello.md")
        vm.addFolder(url: workspace.root)
        await eventually(timeout: .seconds(3), message: "reloadFolder completion") {
            !self.vm.isLoading && !self.vm.folders.isEmpty && self.vm.folders[0].nodesGeneration > 0
        }
        let nodes = vm.folders[0].nodes
        #expect(nodes.contains { $0.name == "hello.md" })
    }

    @Test("重複 addFolder は reloadFolder のみ実行してエントリを増やさない")
    func addFolderDuplicateDoesNotAppend() async throws {
        vm.addFolder(url: workspace.root)
        vm.addFolder(url: workspace.root)
        #expect(vm.folders.count == 1)
    }

    // MARK: - ソート順

    @Test("ノードはディレクトリ優先・同種はアルファベット順")
    func nodesAreSortedDirFirstThenAlpha() async throws {
        try workspace.write("zfile.md", to: "zfile.md")
        try workspace.write("afile.md", to: "afile.md")
        let subdir = try workspace.makeDir("mdir")
        _ = subdir  // ディレクトリは子がないと除外されるため子ファイルを追加
        try workspace.write("child.md", to: "mdir/child.md")

        vm.addFolder(url: workspace.root)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && self.vm.folders.first.map { $0.nodesGeneration > 0 } ?? false
        }
        let nodes = vm.folders[0].nodes
        // 先頭はディレクトリ
        #expect(nodes.first?.isDirectory == true)
        // ファイル群はアルファベット順
        let fileNames = nodes.filter { !$0.isDirectory }.map(\.name)
        #expect(fileNames == fileNames.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }))
    }

    // MARK: - 隠しファイル

    @Test("showHiddenFiles=false（デフォルト）では隠しファイルは表示されない")
    func hiddenFilesExcludedByDefault() async throws {
        try workspace.write("visible.md", to: "visible.md")
        try workspace.write(".hidden.md", to: ".hidden.md")

        vm.addFolder(url: workspace.root)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && self.vm.folders.first.map { $0.nodesGeneration > 0 } ?? false
        }
        let names = vm.folders[0].nodes.map(\.name)
        #expect(names.contains("visible.md"))
        #expect(!names.contains(".hidden.md"))
    }

    // MARK: - removeFolder

    @Test("removeFolder で対象 WorkspaceFolder が削除される")
    func removeFolderDeletesEntry() async throws {
        vm.addFolder(url: workspace.root)
        let id = try #require(vm.folders.first?.id)
        vm.removeFolder(id: id)
        #expect(vm.folders.isEmpty)
    }

    @Test("存在しない UUID を removeFolder しても crash しない")
    func removeFolderUnknownIdIsNoop() {
        vm.removeFolder(id: UUID())
        #expect(vm.folders.isEmpty)
    }

    // MARK: - reloadFolder

    @Test("reloadFolder 後にファイル変更が反映される")
    func reloadFolderPicksUpNewFile() async throws {
        vm.addFolder(url: workspace.root)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && self.vm.folders.first.map { $0.nodesGeneration > 0 } ?? false
        }
        let beforeCount = vm.folders[0].nodes.count
        try workspace.write("newfile.md", to: "newfile.md")
        let id = try #require(vm.folders.first?.id)
        vm.reloadFolder(id: id)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && self.vm.folders.first.map { $0.nodes.count > beforeCount } ?? false
        }
        #expect(vm.folders[0].nodes.contains { $0.name == "newfile.md" })
    }

    // MARK: - createNewFile

    @Test("createNewFile は Untitled.md を作成して newFilePaths に追加する")
    func createNewFileCreatesUntitled() async throws {
        vm.addFolder(url: workspace.root)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && self.vm.folders.first.map { $0.nodesGeneration > 0 } ?? false
        }
        let created = try vm.createNewFile(in: workspace.root)
        #expect(created.lastPathComponent == "Untitled.md")
        #expect(FileManager.default.fileExists(atPath: created.path))
        #expect(vm.isNewFile(created))
    }

    @Test("createNewFile は既存 Untitled.md を避けて Untitled-1.md を作る")
    func createNewFileDeduplicated() async throws {
        vm.addFolder(url: workspace.root)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && self.vm.folders.first.map { $0.nodesGeneration > 0 } ?? false
        }
        let first = try vm.createNewFile(in: workspace.root)
        let second = try vm.createNewFile(in: workspace.root)
        #expect(first.lastPathComponent == "Untitled.md")
        #expect(second.lastPathComponent == "Untitled-1.md")
    }

    @Test("createNewFileInRoot はフォルダ未設定で NSError を投げる")
    func createNewFileInRootThrowsWhenNoFolder() async throws {
        #expect(throws: (any Error).self) {
            try self.vm.createNewFileInRoot()
        }
    }

    // MARK: - New file badge tracking

    @Test("markFileAsNew → isNewFile → clearNewMark の一連の流れ")
    func newFileBadgeLifecycle() throws {
        let url = workspace.url("badge-test.md")
        #expect(!vm.isNewFile(url))
        vm.markFileAsNew(url)
        #expect(vm.isNewFile(url))
        vm.clearNewMark(for: url)
        #expect(!vm.isNewFile(url))
    }

    @Test("standardized URL で同一ファイルを追跡できる")
    func newFileBadgeUsesStandardizedPath() throws {
        let canonical = workspace.url("sym.md")
        let doubled = workspace.url("./sym.md")
        vm.markFileAsNew(canonical)
        #expect(vm.isNewFile(doubled))
    }

    // MARK: - clearWorkspace

    @Test("clearWorkspace で全状態がリセットされる")
    func clearWorkspaceResetsAll() async throws {
        try workspace.write("f.md", to: "f.md")
        vm.addFolder(url: workspace.root)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && self.vm.folders.first.map { $0.nodesGeneration > 0 } ?? false
        }
        vm.markFileAsNew(workspace.url("f.md"))
        vm.selectedNode = vm.folders[0].nodes.first
        vm.clearWorkspace()
        #expect(vm.folders.isEmpty)
        #expect(vm.selectedNode == nil)
        #expect(vm.isLoading == false)
        #expect(vm.newFilePaths.isEmpty)
    }

    // MARK: - Notifications

    @Test("addFolder は workspaceRootChanged を発行する")
    func addFolderPostsWorkspaceRootChanged() async throws {
        // テスト専用の VM + ワークスペースを使い、並列テストからの通知と混同しない。
        let localWS = try TempWorkspace()
        let localVM = FileTreeViewModel()
        var received: URL?
        let token = NotificationCenter.default.addObserver(
            forName: .workspaceRootChanged,
            object: localWS.root,   // object フィルタでこのテスト専用 URL のみ受け取る
            queue: nil
        ) { notification in
            received = notification.object as? URL
        }
        defer { NotificationCenter.default.removeObserver(token) }

        localVM.addFolder(url: localWS.root)
        await eventually(timeout: .seconds(2)) { received != nil }
        #expect(received == localWS.root)
    }

    // MARK: - setScopedWorktree

    @Test("setScopedWorktree は既存フォルダを置き換えて worktree のみにする")
    func setScopedWorktreeReplacesFolders() async throws {
        let otherDir = try TempWorkspace()
        vm.addFolder(url: otherDir.root)
        await eventually(timeout: .seconds(3)) {
            !self.vm.isLoading && !self.vm.folders.isEmpty
        }
        vm.setScopedWorktree(workspace.root)
        #expect(vm.folders.count == 1)
        #expect(vm.folders[0].url == workspace.root)
        #expect(vm.selectedNode == nil)
        #expect(vm.newFilePaths.isEmpty)
    }

    // MARK: - Compile-time regression guard

    @Test("FileTreeViewModel の主要 public API が揃っている（コンパイル時回帰ガード）")
    func publicApiExists() {
        let addFolderRef: (FileTreeViewModel) -> (URL) -> Void = FileTreeViewModel.addFolder(url:)
        let removeFolderRef: (FileTreeViewModel) -> (UUID) -> Void = FileTreeViewModel.removeFolder
        let clearRef: (FileTreeViewModel) -> () -> Void = FileTreeViewModel.clearWorkspace
        let markRef: (FileTreeViewModel) -> (URL) -> Void = FileTreeViewModel.markFileAsNew
        let clearMarkRef: (FileTreeViewModel) -> (URL) -> Void = FileTreeViewModel.clearNewMark(for:)
        let isNewRef: (FileTreeViewModel) -> (URL) -> Bool = FileTreeViewModel.isNewFile
        _ = addFolderRef; _ = removeFolderRef; _ = clearRef
        _ = markRef; _ = clearMarkRef; _ = isNewRef
    }
}
