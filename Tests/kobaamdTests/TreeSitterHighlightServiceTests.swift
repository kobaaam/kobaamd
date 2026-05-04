import AppKit
import Testing
@testable import kobaamd

@MainActor
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

    @Test("applyIncrementalHighlight: 編集範囲外の属性が保持される")
    func incrementalPreservesOutOfRangeAttributes() {
        // 2段落の文書で、1段落目のみを編集した後に2段落目のハイライトが消えないことを確認
        let fullText = "# Heading\n\nSome body text"
        let storage = NSTextStorage(string: fullText)
        // まず初回フルハイライト
        let service = TreeSitterHighlightService()
        service.highlight(storage)
        // 1段落目の末尾に1文字追加を模擬（editedRange = heading のみ、changeInLength = 1）
        let headingRange = NSRange(location: 0, length: 9) // "# Heading"
        service.applyIncrementalHighlight(
            textStorage: storage,
            editedRange: headingRange,
            changeInLength: 1
        )
        // 2段落目の先頭 (index 11 = "S") に foregroundColor が設定されていること
        let bodyStart = fullText.count - "Some body text".count
        if bodyStart < storage.length {
            let attrs = storage.attributes(at: bodyStart, effectiveRange: nil)
            #expect(attrs[.foregroundColor] != nil)
        }
    }

    @Test("パース不能な入力でもクラッシュせずフォールバックする")
    func unparseableInputDoesNotCrash() {
        // 大量の特殊文字・制御文字でパースを困難にした入力
        let weirdText = String(repeating: "\u{0000}\u{FFFD}<<<>>>", count: 100)
        let storage = NSTextStorage(string: weirdText)
        // クラッシュしないこと（fallback に倒れること）を検証
        TreeSitterHighlightService().highlight(storage)
        #expect(storage.string == weirdText)
    }
}
