import Testing
@testable import kobaamd

@Suite("MarkdownService")
struct MarkdownServiceTests {
    let svc = MarkdownService()

    /// `<body>` 〜 `</body>` のコンテンツだけ取り出す。
    private func body(of html: String) -> String {
        guard let start = html.range(of: "<body>"),
              let end = html.range(of: "</body>") else { return html }
        return String(html[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 見出し

    @Test("h1 タグとコンテンツが生成されること")
    func h1Rendering() {
        let html = body(of: svc.toHTML("# Hello"))
        #expect(html.contains("<h1") && html.contains(">Hello</h1>"))
    }

    @Test("h2 タグとコンテンツが生成されること")
    func h2Rendering() {
        let html = body(of: svc.toHTML("## Section"))
        #expect(html.contains("<h2") && html.contains(">Section</h2>"))
    }

    @Test("h3 タグとコンテンツが生成されること")
    func h3Rendering() {
        let html = body(of: svc.toHTML("### Sub"))
        #expect(html.contains("<h3") && html.contains(">Sub</h3>"))
    }

    // MARK: - インライン要素

    @Test("太字が <strong> になること")
    func boldRendering() {
        #expect(body(of: svc.toHTML("**bold**")).contains("<strong>bold</strong>"))
    }

    @Test("斜体が <em> になること")
    func italicRendering() {
        #expect(body(of: svc.toHTML("_italic_")).contains("<em>italic</em>"))
    }

    @Test("打ち消し線が <del> になること")
    func strikethroughRendering() {
        #expect(body(of: svc.toHTML("~~del~~")).contains("<del>del</del>"))
    }

    @Test("インラインコードが <code> になること")
    func inlineCodeRendering() {
        #expect(body(of: svc.toHTML("`code`")).contains("<code>code</code>"))
    }

    @Test("リンクに href とテキストが含まれること")
    func linkRendering() {
        let html = body(of: svc.toHTML("[text](https://example.com)"))
        #expect(html.contains("href=\"https://example.com\""))
        #expect(html.contains(">text<"))
    }

    // MARK: - ブロック要素

    @Test("箇条書きが <ul><li> を含むこと")
    func unorderedList() {
        let html = body(of: svc.toHTML("- item1\n- item2"))
        #expect(html.contains("<ul"))
        #expect(html.contains("<li>"))
    }

    @Test("番号付きリストが <ol> を含むこと")
    func orderedList() {
        #expect(body(of: svc.toHTML("1. first\n2. second")).contains("<ol"))
    }

    @Test("コードブロックが <pre> と言語クラスを含むこと")
    func codeBlock() {
        let html = body(of: svc.toHTML("```swift\nlet x = 1\n```"))
        #expect(html.contains("<pre"))
        #expect(html.contains("language-swift"))
    }

    @Test("引用が <blockquote> になること")
    func blockquote() {
        #expect(body(of: svc.toHTML("> quote")).contains("<blockquote"))
    }

    @Test("水平線が <hr> になること")
    func horizontalRule() {
        #expect(body(of: svc.toHTML("---")).contains("<hr"))
    }

    // MARK: - HTML エスケープ（セキュリティ）

    @Test("テキスト中の < > がエスケープされること")
    func anglebracketsInTextAreEscaped() {
        let html = body(of: svc.toHTML("Use <tag> and > literally"))
        #expect(html.contains("&lt;tag&gt;"))
        #expect(html.contains("&gt;"))
    }

    @Test("見出しテキスト中の特殊文字がエスケープされること")
    func headingTextIsEscaped() {
        let html = body(of: svc.toHTML("# A < B & C"))
        #expect(html.contains("<h1"))
        #expect(html.contains("A &lt; B &amp; C</h1>"))
    }

    @Test("& がエスケープされること")
    func ampersandEscaping() {
        #expect(body(of: svc.toHTML("A & B")).contains("&amp;"))
    }

    // MARK: - ドキュメント構造

    @Test("DOCTYPE が含まれること")
    func outputContainsDoctype() {
        #expect(svc.toHTML("hello").contains("<!DOCTYPE html>"))
    }

    @Test("空入力でも有効な HTML スケルトンが生成されること")
    func emptyInputProducesValidHTML() {
        let html = svc.toHTML("")
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<body>"))
        #expect(html.contains("</body>"))
    }

    @Test("Mermaid スクリプトタグが含まれること")
    func mermaidScriptPresent() {
        #expect(svc.toHTML("test").contains("mermaid"))
    }

    // MARK: - テーブル

    @Test("テーブルが table/td/th 要素を含むこと")
    func tableRendering() {
        let md = "| Name | Value |\n| --- | --- |\n| A | 1 |"
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("<table"))
        #expect(html.contains("<td>A</td>"))
        #expect(html.contains("<th>"))
    }

    // MARK: - Mermaid コードブロック

    @Test("Mermaid コードブロックに language-mermaid クラスが付くこと")
    func mermaidBlockHasLanguageClass() {
        let md = "```mermaid\ngraph TD;\nA-->B;\n```"
        #expect(svc.toHTML(md).contains("language-mermaid"))
    }

    // MARK: - チェックボックス

    @Test("タスクリストに input[type=checkbox] が含まれること")
    func checkboxRendering() {
        let md = "- [ ] todo\n- [x] done"
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("type=\"checkbox\""))
        #expect(html.contains("checked"))
    }

    @Test("チェックボックスリストに箇条書き記号が出ないこと")
    func checkboxHasNoListStyle() {
        let html = svc.toHTML("- [ ] item")
        // list-style:none の CSS が存在すること
        #expect(html.contains("list-style:none") || html.contains("list-style: none"))
    }

    @Test("チェックボックス li に data-source-line-start 属性が付くこと")
    func checkboxListItemHasSourceLineAttr() {
        let md = "- [ ] todo\n- [x] done"
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("<li data-source-line-start="))
    }

    @Test("通常リストの li に data-source-line-start 属性が付くこと")
    func listItemHasSourceLineAttr() {
        let md = "- item1\n- item2"
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("<li data-source-line-start="))
    }

    // MARK: - data-source-line-* 属性（プレビュー同期）

    @Test("h1 に data-source-line-start 属性が付くこと")
    func h1HasSourceLineAttr() {
        let html = body(of: svc.toHTML("# Title"))
        #expect(html.contains("data-source-line-start=\"1\""))
    }

    @Test("段落に data-source-line-start 属性が付くこと")
    func paragraphHasSourceLineAttr() {
        let html = body(of: svc.toHTML("Hello world"))
        #expect(html.contains("data-source-line-start=\"1\""))
    }

    @Test("コードブロックに data-source-line-start 属性が付くこと")
    func codeBlockHasSourceLineAttr() {
        let html = body(of: svc.toHTML("```swift\nlet x = 1\n```"))
        #expect(html.contains("<pre data-source-line-start="))
    }

    @Test("blockquote に data-source-line-start 属性が付くこと")
    func blockquoteHasSourceLineAttr() {
        let html = body(of: svc.toHTML("> quote"))
        #expect(html.contains("<blockquote data-source-line-start="))
    }

    @Test("テーブルに data-source-line-start 属性が付くこと")
    func tableHasSourceLineAttr() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("<table data-source-line-start="))
    }

    @Test("テーブル行（tr）に data-source-line-start 属性が付くこと")
    func tableRowHasSourceLineAttr() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("<tr data-source-line-start="))
    }

    @Test("複数ブロックの source-line が正しい行番号になること")
    func multiBlockSourceLines() {
        let md = "# Heading\n\nParagraph"
        let html = body(of: svc.toHTML(md))
        // 見出しは1行目、空行を挟んで段落は3行目
        #expect(html.contains("data-source-line-start=\"1\""))
        #expect(html.contains("data-source-line-start=\"3\""))
    }

    @Test("テーブル本文行の source-line が連番になること")
    func tableBodyRowSourceLines() {
        let md = "| H |\n|---|\n| R1 |\n| R2 |"
        let html = body(of: svc.toHTML(md))
        // R1 は3行目、R2 は4行目
        #expect(html.contains("data-source-line-start=\"3\""))
        #expect(html.contains("data-source-line-start=\"4\""))
    }

    @Test("toBodyHTML も data-source-line-start 属性を含むこと")
    func bodyHTMLAlsoHasSourceLineAttr() {
        let html = svc.toBodyHTML("# Hello")
        #expect(html.contains("data-source-line-start=\"1\""))
    }

    @Test("data-source-line-end が data-source-line-start 以上の値になること")
    func sourceLineEndGeStart() {
        let md = "# Title\n\nFirst paragraph.\n\nSecond paragraph."
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("data-source-line-end="))
        // end >= start の検証: start="1" end="1" のような対応
        #expect(html.contains("data-source-line-start=\"1\" data-source-line-end=\"1\""))
    }
}
