import AppKit
import Testing
@testable import kobaamd

@MainActor
@Suite("HighlightService")
struct HighlightServiceTests {

    private func attrs(for text: String, at location: Int = 0) -> [NSAttributedString.Key: Any] {
        let storage = NSTextStorage(string: text)
        HighlightService().highlight(storage)
        guard storage.length > location else { return [:] }
        return storage.attributes(at: location, effectiveRange: nil)
    }

    @Test("空テキストでクラッシュしないこと")
    func emptyTextDoesNotCrash() {
        let storage = NSTextStorage(string: "")
        HighlightService().highlight(storage)
        #expect(storage.string == "")
    }

    @Test("# Heading に foregroundColor が設定されること")
    func headingAppliesForegroundColor() {
        #expect(attrs(for: "# Heading", at: 0)[.foregroundColor] != nil)
    }

    @Test("**bold** にボールドフォントが適用されること")
    func boldSyntaxAppliesBoldFont() {
        let font = attrs(for: "**bold**", at: 2)[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("`code` に foregroundColor が設定されること")
    func inlineCodeAppliesForegroundColor() {
        #expect(attrs(for: "`code`", at: 1)[.foregroundColor] != nil)
    }

    @Test("~~strike~~ に strikethroughStyle 属性が設定されること")
    func strikethroughAddsStyle() {
        #expect(attrs(for: "~~strike~~", at: 2)[.strikethroughStyle] != nil)
    }

    @Test("> quote に obliqueness 属性が設定されること")
    func quoteAppliesObliqueness() {
        #expect(attrs(for: "> quote", at: 2)[.obliqueness] != nil)
    }

    @Test("[text](url) に foregroundColor が設定されること")
    func linkAppliesForegroundColor() {
        #expect(attrs(for: "[text](https://example.com)", at: 1)[.foregroundColor] != nil)
    }

    @Test("fenced code block に foregroundColor が設定されること")
    func fencedCodeBlockAppliesForegroundColor() {
        let block = "```\nlet a = 1\n```"
        #expect(attrs(for: block, at: 0)[.foregroundColor] != nil)
    }
}
