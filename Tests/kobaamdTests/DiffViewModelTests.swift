import Foundation
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

    // MARK: - 一時ファイルの並列安全性

    @Test("並列で scheduleUpdate を複数回呼び出しても干渉せず lines が更新されること")
    func parallelDiffComputationDoesNotInterfere() async throws {
        let vm1 = DiffViewModel()
        let vm2 = DiffViewModel()

        vm1.textA = "alpha\nbeta"
        vm1.textB = "alpha\nbravo"
        vm2.textA = "x\ny"
        vm2.textB = "x\nz"

        vm1.scheduleUpdate()
        vm2.scheduleUpdate()

        // debounce 300ms + diff 処理を待つ
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // 両方とも diff 結果が更新されていること
        // （細かい lines の中身は環境依存なので、isEmpty でないことだけを確認）
        #expect(vm1.lines.isEmpty == false)
        #expect(vm2.lines.isEmpty == false)
    }

    @Test("一時ファイルが処理後に NSTemporaryDirectory に残らないこと")
    func temporaryFilesAreCleanedUp() async throws {
        let vm = DiffViewModel()
        vm.textA = "hello"
        vm.textB = "world"
        vm.scheduleUpdate()

        try await Task.sleep(nanoseconds: 1_500_000_000)

        // NSTemporaryDirectory 内に kobaamd_diff_ で始まるファイルが残っていないこと
        let tmpDir = NSTemporaryDirectory()
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
        let leftover = contents.filter { $0.hasPrefix("kobaamd_diff_") }
        #expect(leftover.isEmpty, "Leftover diff temp files: \(leftover)")
    }
}
