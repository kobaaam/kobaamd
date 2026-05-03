import AppKit
import Testing
@testable import kobaamd

@Suite("TreeSitterHighlightService")
struct TreeSitterHighlightServiceTests {

    @Test("空テキストでクラッシュしない")
    func emptyTextDoesNotCrash() {
        let storage = NSTextStorage(string: "")
        TreeSitterHighlightService().highlight(storage)
        #expect(storage.string == "")
    }

    @Test("# 見出しに foregroundColor が設定される")
    func headingAppliesForegroundColor() {
        let storage = NSTextStorage(string: "# Heading")
        TreeSitterHighlightService().highlight(storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.foregroundColor] != nil)
    }

    @Test("fenced code block に foregroundColor が設定される")
    func fencedCodeBlockAppliesForegroundColor() {
        let storage = NSTextStorage(string: "```\nlet a = 1\n```")
        TreeSitterHighlightService().highlight(storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.foregroundColor] != nil)
    }

    @Test("applyIncrementalHighlight がフォールバックでフルリビルドする")
    func incrementalFallsBackToFullRebuild() {
        let storage = NSTextStorage(string: "# Heading")
        TreeSitterHighlightService().applyIncrementalHighlight(
            textStorage: storage,
            editedRange: NSRange(location: 0, length: 9),
            changeInLength: 0
        )
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.foregroundColor] != nil)
    }
}
