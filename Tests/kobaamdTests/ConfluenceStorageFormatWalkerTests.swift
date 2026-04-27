import Testing
@testable import kobaamd

@Suite("ConfluenceStorageFormatWalker")
struct ConfluenceStorageFormatWalkerTests {
    let svc = ConfluenceService()

    @Test("h1 見出しが storage format に変換されること")
    func testHeadingH1() {
        #expect(svc.convertToStorageFormat("# Hello") == "<h1>Hello</h1>")
    }

    @Test("h2 見出しが storage format に変換されること")
    func testHeadingH2() {
        #expect(svc.convertToStorageFormat("## World") == "<h2>World</h2>")
    }

    @Test("h3 見出しが storage format に変換されること")
    func testHeadingH3() {
        #expect(svc.convertToStorageFormat("### Sub") == "<h3>Sub</h3>")
    }

    @Test("通常テキストが段落に変換されること")
    func testParagraph() {
        #expect(svc.convertToStorageFormat("Hello world") == "<p>Hello world</p>")
    }

    @Test("言語付きコードブロックに language パラメータが入ること")
    func testCodeBlockWithLanguage() {
        let html = svc.convertToStorageFormat("```swift\nlet x = 1\n```")
        #expect(html.contains("<ac:structured-macro ac:name=\"code\">"))
        #expect(html.contains("<ac:parameter ac:name=\"language\">swift</ac:parameter>"))
    }

    @Test("言語なしコードブロックは language=none になること")
    func testCodeBlockNoLanguage() {
        let html = svc.convertToStorageFormat("```\nlet x = 1\n```")
        #expect(html.contains("<ac:parameter ac:name=\"language\">none</ac:parameter>"))
    }

    @Test("太字が strong に変換されること")
    func testStrong() {
        #expect(svc.convertToStorageFormat("**bold**").contains("<strong>bold</strong>"))
    }

    @Test("斜体が em に変換されること")
    func testEmphasis() {
        #expect(svc.convertToStorageFormat("_italic_").contains("<em>italic</em>"))
    }

    @Test("リンクが a タグに変換されること")
    func testLink() {
        let html = svc.convertToStorageFormat("[label](https://example.com)")
        #expect(html.contains("<a href=\"https://example.com\">label</a>"))
    }
}
