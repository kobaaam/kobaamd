import Foundation
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
    func openDroppedFileAddsDirectoryToFileTree() async {
        let vm = AppViewModel()
        // /tmp は実在するディレクトリ
        let dirURL = URL(fileURLWithPath: "/tmp")
        await vm.openDroppedFile(url: dirURL)
        #expect(vm.fileTreeViewModel.folders.contains(where: { $0.url == dirURL }))
    }

    // MARK: - AI Inline Space Trigger Tests

    @Test("showAIInlinePrompt で isAIInlinePromptVisible が true になること")
    func showAIInlinePromptSetsVisible() {
        let vm = AppViewModel()
        vm.showAIInlinePrompt(cursorLocation: 5)
        #expect(vm.isAIInlinePromptVisible == true)
        #expect(vm.aiInlineCursorLocation == 5)
        #expect(vm.pendingAIText.isEmpty)
        #expect(vm.isAIPendingConfirmation == false)
    }

    @Test("rejectPendingAIText で状態がリセットされること")
    func rejectPendingAITextResetsState() {
        let vm = AppViewModel()
        // 事前に状態をセット
        vm.pendingAIText = "生成済みテキスト"
        vm.isAIPendingConfirmation = true
        vm.isAIGenerating = false

        vm.rejectPendingAIText()

        #expect(vm.pendingAIText.isEmpty)
        #expect(vm.isAIPendingConfirmation == false)
        #expect(vm.isAIGenerating == false)
        #expect(vm.isAIInlinePromptVisible == false)
    }

    @Test("acceptPendingAIText で pendingAIText が editorText の正しい位置に挿入されること")
    func acceptPendingAITextInsertsAtCursorLocation() {
        let vm = AppViewModel()
        vm.editorText = "Hello World"
        vm.aiInlineCursorLocation = 5  // "Hello" の直後
        vm.pendingAIText = " Beautiful"

        vm.acceptPendingAIText()

        #expect(vm.editorText == "Hello Beautiful World")
        #expect(vm.pendingAIText.isEmpty)
        #expect(vm.isAIPendingConfirmation == false)
    }

    @Test("acceptPendingAIText で pendingAIText が空のとき何も挿入しないこと")
    func acceptPendingAITextWithEmptyPendingDoesNothing() {
        let vm = AppViewModel()
        vm.editorText = "Hello"
        vm.pendingAIText = ""

        vm.acceptPendingAIText()

        #expect(vm.editorText == "Hello")
    }

    @Test("startAIInlineFromSpace でストリーミング完了後に pendingAIText にトークンが蓄積されること")
    func startAIInlineFromSpaceAccumulatesPendingText() async throws {
        let mock = MockAIService()
        mock.tokensToEmit = ["こんにちは", "、", "世界"]
        let vm = AppViewModel(aiService: mock)
        vm._testProvider = .openai
        vm.editorText = "Hello"
        vm.aiInlineCursorLocation = 5

        vm.startAIInlineFromSpace(prompt: "続きを書いて")

        // ストリーミング完了を待機
        try await Task.sleep(for: .milliseconds(300))

        #expect(vm.pendingAIText == "こんにちは、世界")
        #expect(vm.isAIGenerating == false)
        #expect(vm.isAIPendingConfirmation == true)
    }

    @Test("startAIInlineFromSpace でエラー発生時に pendingAIText にエラーメッセージが入ること")
    func startAIInlineFromSpaceHandlesError() async throws {
        let mock = MockAIService()
        mock.tokensToEmit = ["部分"]
        mock.errorToThrow = AIError.invalidResponse
        let vm = AppViewModel(aiService: mock)
        vm._testProvider = .openai
        vm.editorText = ""
        vm.aiInlineCursorLocation = 0

        vm.startAIInlineFromSpace(prompt: "テスト")

        try await Task.sleep(for: .milliseconds(300))

        #expect(vm.pendingAIText.contains("AI エラー"))
        #expect(vm.isAIGenerating == false)
        #expect(vm.isAIPendingConfirmation == true)
    }

    @Test("rejectPendingAIText で生成中タスクがキャンセルされること")
    func rejectPendingAITextCancelsGeneratingTask() async throws {
        let mock = MockAIService()
        mock.tokensToEmit = ["Token1", "Token2"]
        let vm = AppViewModel(aiService: mock)
        vm._testProvider = .openai

        vm.startAIInlineFromSpace(prompt: "テスト")
        // 即座にキャンセル
        vm.rejectPendingAIText()

        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.pendingAIText.isEmpty)
        #expect(vm.isAIPendingConfirmation == false)
        #expect(vm.isAIGenerating == false)
    }

    @Test("acceptPendingAIText で絵文字を含むテキストでも正しい位置に挿入されること")
    func acceptPendingAITextWithEmojiText() {
        let vm = AppViewModel()
        // 🇯🇵 は Character では 1 だが UTF-16 では 4 code units
        vm.editorText = "🇯🇵Hello"
        // UTF-16 offset 8 は "🇯🇵Hell" の直後
        vm.aiInlineCursorLocation = 8
        vm.pendingAIText = "!"

        vm.acceptPendingAIText()

        // "🇯🇵Hell" + "!" + "o" = "🇯🇵Hell!o"
        #expect(vm.editorText == "🇯🇵Hell!o")
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
}
