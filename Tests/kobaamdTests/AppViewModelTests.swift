import Foundation
import AppKit
import Testing
@testable import kobaamd

@Suite("AppViewModel")
@MainActor
struct AppViewModelTests {

    @Test("openInTab でタブ数が増えること")
    func openInTabIncreasesTabCount() {
        let vm = AppViewModel()
        vm.openInTab(url: URL(fileURLWithPath: "/tmp/doc1.md"), content: "a")
        #expect(vm.tabs.count == 1)
    }

    @Test("同じ URL で openInTab を2回呼んでも duplicate にならないこと")
    func openingSameURLTwicePreservesTabCount() {
        let vm = AppViewModel()
        let url = URL(fileURLWithPath: "/tmp/doc2.md")
        vm.openInTab(url: url, content: "first")
        vm.openInTab(url: url, content: "second")
        #expect(vm.tabs.count == 1)
    }

    @Test("newTab で空タブが追加されること")
    func newTabAddsEmptyTab() {
        let vm = AppViewModel()
        vm.newTab()
        #expect(vm.tabs.count == 1)
        #expect(vm.tabs.first?.content == "")
    }

    @Test("closeTab でタブ数が減ること")
    func closeTabDecreasesTabCount() {
        let vm = AppViewModel()
        vm.openInTab(url: URL(fileURLWithPath: "/tmp/a.md"), content: "a")
        vm.openInTab(url: URL(fileURLWithPath: "/tmp/b.md"), content: "b")
        let id = vm.tabs.first!.id
        vm.closeTab(id: id)
        #expect(vm.tabs.count == 1)
    }

    @Test("最後のタブを閉じると editorText が空になること")
    func closingLastTabClearsEditorText() {
        let vm = AppViewModel()
        vm.openInTab(url: URL(fileURLWithPath: "/tmp/last.md"), content: "content")
        vm.closeTab(id: vm.tabs.first!.id)
        #expect(vm.editorText.isEmpty)
    }

    @Test("switchToTab で activeTabID が変わること")
    func switchToTabUpdatesActiveID() {
        let vm = AppViewModel()
        vm.openInTab(url: URL(fileURLWithPath: "/tmp/a.md"), content: "a")
        vm.openInTab(url: URL(fileURLWithPath: "/tmp/b.md"), content: "b")
        let secondID = vm.tabs[1].id
        vm.switchToTab(id: secondID)
        #expect(vm.activeTabID == secondID)
    }

    @Test("markSaved で isDirty が false になること")
    func markSavedClearsDirtyFlag() {
        let vm = AppViewModel()
        vm.markEdited()
        vm.markSaved()
        #expect(vm.isDirty == false)
    }

    @Test("markEdited で isDirty が true になること")
    func markEditedSetsDirtyFlag() {
        let vm = AppViewModel()
        vm.markEdited()
        #expect(vm.isDirty == true)
    }

    @Test("updateEditorText で editorText が更新されること")
    func updateEditorTextAppliesText() {
        let vm = AppViewModel()
        vm.updateEditorText("Updated")
        #expect(vm.editorText == "Updated")
    }

    @Test("flushActiveTab でアクティブタブに editorText が保存されること")
    func flushActiveTabSavesEditorText() {
        let vm = AppViewModel()
        vm.newTab()
        vm.updateEditorText("Persisted Content")
        vm.flushActiveTab()
        let activeTab = vm.tabs.first(where: { $0.id == vm.activeTabID })
        #expect(activeTab?.content == "Persisted Content")
    }

    @Test("activeTab computed property がアクティブなタブを返すこと")
    func activeTabReturnsCorrectTab() {
        let vm = AppViewModel()
        vm.openInTab(url: URL(fileURLWithPath: "/tmp/x.md"), content: "x")
        #expect(vm.activeTab?.url?.lastPathComponent == "x.md")
    }

    @Test("openDroppedFile: サポート対象外拡張子(.png)ではタブが開かれないこと")
    func openDroppedFileIgnoresUnsupportedExtension() async {
        let vm = AppViewModel()
        let url = URL(fileURLWithPath: "/tmp/image.png")
        await vm.openDroppedFile(url: url)
        #expect(vm.tabs.isEmpty)
    }

    @Test("openDroppedFile: ディレクトリURLではfileTreeViewModelにフォルダが追加されること")
    func openDroppedFileAddsDirectoryToFileTree() async throws {
        let vm = AppViewModel()
        let dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        await vm.openDroppedFile(url: dirURL)
        #expect(vm.fileTreeViewModel.folders.contains(where: {
            $0.url.standardizedFileURL == dirURL.standardizedFileURL
        }))
    }

    // MARK: - Viewer Mode Tests

    @Test("PreviewMode に viewer ケースが存在し、allCases に含まれること")
    func previewModeIncludesViewerCase() {
        #expect(PreviewMode.allCases.contains(.viewer))
        #expect(PreviewMode.allCases.count == 4)
    }

    @Test("toggleViewerMode で .viewer に切り替わり、もう一度呼ぶと前のモードに戻ること")
    func toggleViewerModeSwitchesBetweenViewerAndPrevious() {
        let vm = AppViewModel()
        vm.selectedFileURL = URL(fileURLWithPath: "/tmp/doc.md")
        vm.previewMode = .split

        vm.toggleViewerMode()
        #expect(vm.previewMode == .viewer)
        #expect(vm.previousPreviewMode == .split)

        vm.toggleViewerMode()
        #expect(vm.previewMode == .split)
    }

    @Test("toggleViewerMode は非Markdownファイルでは動作しないこと")
    func toggleViewerModeIgnoresNonMarkdownFiles() {
        let vm = AppViewModel()
        vm.selectedFileURL = URL(fileURLWithPath: "/tmp/diagram.d2")
        vm.previewMode = .split

        vm.toggleViewerMode()
        #expect(vm.previewMode == .split)
    }

    @Test("PreviewMode の rawValue が安定していること（永続化フォールバック確認）")
    func previewModeRawValuesAreStable() {
        #expect(PreviewMode(rawValue: "Viewer") == .viewer)
        #expect(PreviewMode(rawValue: "UnknownMode") == nil)
    }

    @Test("syncOpenTabsFromDiskIfClean reloads clean tabs from disk")
    func syncOpenTabsFromDiskIfCleanUpdatesCleanTab() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("page.html")
        try "<p>old</p>".write(to: file, atomically: true, encoding: .utf8)

        let vm = AppViewModel()
        vm.openInTab(url: file, content: "<p>old</p>")
        try "<p>new</p>".write(to: file, atomically: true, encoding: .utf8)

        vm.syncOpenTabsFromDiskIfClean()

        #expect(vm.editorText == "<p>new</p>")
        #expect(vm.isDirty == false)
        #expect(vm.tabs.first?.content == "<p>new</p>")
    }

    @Test("resolvedActiveFileContent prefers disk for clean markdown tab")
    func resolvedActiveFileContentPrefersDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("doc.md")
        try "# old".write(to: file, atomically: true, encoding: .utf8)

        let vm = AppViewModel()
        vm.openInTab(url: file, content: "# old")
        try "# new".write(to: file, atomically: true, encoding: .utf8)

        #expect(vm.resolvedActiveFileContent() == "# new")
    }

    @Test("syncOpenTabsFromDiskIfClean skips dirty tabs")
    func syncOpenTabsFromDiskIfCleanSkipsDirtyTab() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("page.html")
        try "<p>disk</p>".write(to: file, atomically: true, encoding: .utf8)

        let vm = AppViewModel()
        vm.openInTab(url: file, content: "<p>disk</p>")
        vm.updateEditorText("<p>editing</p>")
        try "<p>external</p>".write(to: file, atomically: true, encoding: .utf8)

        vm.syncOpenTabsFromDiskIfClean()

        #expect(vm.editorText == "<p>editing</p>")
        #expect(vm.isDirty == true)
    }

}
