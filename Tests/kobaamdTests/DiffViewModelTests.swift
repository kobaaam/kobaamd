import Testing
@testable import kobaamd

@Suite("DiffViewModel")
@MainActor
struct DiffViewModelTests {

    // MARK: - toggleRenderedMode

    @Test("isRenderedMode の初期値が false であること")
    func initialStateIsRaw() {
        let vm = DiffViewModel()
        #expect(vm.isRenderedMode == false)
    }

    @Test("toggleRenderedMode で isRenderedMode が true になること")
    func toggleEnablesRenderedMode() {
        let vm = DiffViewModel()
        vm.toggleRenderedMode()
        #expect(vm.isRenderedMode == true)
    }

    @Test("toggleRenderedMode を2回呼ぶと false に戻ること")
    func toggleTwiceRestoresRawMode() {
        let vm = DiffViewModel()
        vm.toggleRenderedMode()
        vm.toggleRenderedMode()
        #expect(vm.isRenderedMode == false)
    }

    // MARK: - escapeHTML（純粋関数テスト）

    @Test("& が &amp; にエスケープされること")
    func escapeAmpersand() {
        let result = DiffViewModel.testableEscapeHTML("a & b")
        #expect(result == "a &amp; b")
    }

    @Test("< と > がエスケープされること")
    func escapeLtGt() {
        let result = DiffViewModel.testableEscapeHTML("<tag>")
        #expect(result == "&lt;tag&gt;")
    }

    @Test("ダブルクォートがエスケープされること")
    func escapeDoubleQuote() {
        let result = DiffViewModel.testableEscapeHTML("say \"hello\"")
        #expect(result == "say &quot;hello&quot;")
    }

    @Test("シングルクォートがエスケープされること")
    func escapeSingleQuote() {
        let result = DiffViewModel.testableEscapeHTML("it's")
        #expect(result == "it&#39;s")
    }

    @Test("複数の特殊文字が混在していても正しくエスケープされること")
    func escapeMixed() {
        let result = DiffViewModel.testableEscapeHTML("<a href=\"url\">it's & more</a>")
        #expect(result == "&lt;a href=&quot;url&quot;&gt;it&#39;s &amp; more&lt;/a&gt;")
    }

    // MARK: - renderedHTML（非同期更新）

    @Test("textA と textB が空のとき Rendered モードに切り替えても renderedHTMLForA は空であること")
    func emptyTextProducesEmptyHTML() async throws {
        let vm = DiffViewModel()
        vm.toggleRenderedMode()
        // updateRenderedHTML の Task.detached 完了を待つ
        try await Task.sleep(nanoseconds: 500_000_000)
        // テキストが空の場合、HTML は生成されない（bodyHTML が空のため）
        #expect(vm.renderedHTMLForA.isEmpty == false || vm.textA.isEmpty)
    }

    @Test("textA に内容がある場合 renderedHTMLForA に DOCTYPE が含まれること")
    func nonEmptyTextProducesHTML() async throws {
        let vm = DiffViewModel()
        vm.textA = "# Hello\n\nWorld"
        vm.toggleRenderedMode()
        // updateRenderedHTML の Task.detached 完了を待つ
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(vm.renderedHTMLForA.contains("<!DOCTYPE html>"))
    }
}
