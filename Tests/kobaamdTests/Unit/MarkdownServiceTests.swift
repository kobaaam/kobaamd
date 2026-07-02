import Testing
@testable import kobaamd

@Suite("MarkdownService")
struct MarkdownServiceTests {
    let svc = MarkdownService()

    // MARK: - 見出し

    @Test("h1 タグとコンテンツが生成されること")
    func h1Rendering() {
        let html = svc.toBodyHTML("# Hello")
        #expect(html.contains("<h1") && html.contains(">Hello</h1>"))
    }

    @Test("h2 タグとコンテンツが生成されること")
    func h2Rendering() {
        let html = svc.toBodyHTML("## Section")
        #expect(html.contains("<h2") && html.contains(">Section</h2>"))
    }

    @Test("h3 タグとコンテンツが生成されること")
    func h3Rendering() {
        let html = svc.toBodyHTML("### Sub")
        #expect(html.contains("<h3") && html.contains(">Sub</h3>"))
    }

    // MARK: - インライン要素

    @Test("太字が <strong> になること")
    func boldRendering() {
        #expect(svc.toBodyHTML("**bold**").contains("<strong>bold</strong>"))
    }

    @Test("斜体が <em> になること")
    func italicRendering() {
        #expect(svc.toBodyHTML("_italic_").contains("<em>italic</em>"))
    }

    @Test("打ち消し線が <del> になること")
    func strikethroughRendering() {
        #expect(svc.toBodyHTML("~~del~~").contains("<del>del</del>"))
    }

    @Test("インラインコードが <code> になること")
    func inlineCodeRendering() {
        #expect(svc.toBodyHTML("`code`").contains("<code>code</code>"))
    }

    @Test("リンクに href とテキストが含まれること")
    func linkRendering() {
        let html = svc.toBodyHTML("[text](https://example.com)")
        #expect(html.contains("href=\"https://example.com\""))
        #expect(html.contains(">text<"))
    }

    // MARK: - ブロック要素

    @Test("箇条書きが <ul><li> を含むこと")
    func unorderedList() {
        let html = svc.toBodyHTML("- item1\n- item2")
        #expect(html.contains("<ul"))
        #expect(html.contains("<li"))
    }

    @Test("番号付きリストが <ol> を含むこと")
    func orderedList() {
        #expect(svc.toBodyHTML("1. first\n2. second").contains("<ol"))
    }

    @Test("コードブロックが <pre> と言語クラスを含むこと")
    func codeBlock() {
        let html = svc.toBodyHTML("```swift\nlet x = 1\n```")
        #expect(html.contains("<pre"))
        #expect(html.contains("language-swift"))
    }

    @Test("引用が <blockquote> になること")
    func blockquote() {
        #expect(svc.toBodyHTML("> quote").contains("<blockquote"))
    }

    @Test("水平線が <hr> になること")
    func horizontalRule() {
        #expect(svc.toBodyHTML("---").contains("<hr"))
    }

    // MARK: - HTML エスケープ（セキュリティ）

    @Test("テキスト中の < > がエスケープされること")
    func anglebracketsInTextAreEscaped() {
        let html = svc.toBodyHTML("Use <tag> and > literally")
        // KMD-242: swift-markdown は <tag> を InlineHTML として扱う。
        // HTMLSanitizer の許可リストに含まれないタグは除去されるため
        // <tag> の内容は出力されない。bare `>` はテキストノードとしてエスケープされる。
        #expect(!html.contains("<tag>"), "<tag> は許可タグでないため除去されるべき")
        #expect(html.contains("&gt;"))
    }

    @Test("見出しテキスト中の特殊文字がエスケープされること")
    func headingTextIsEscaped() {
        let html = svc.toBodyHTML("# A < B & C")
        #expect(html.contains("<h1"))
        #expect(html.contains("A &lt; B &amp; C</h1>"))
    }

    @Test("& がエスケープされること")
    func ampersandEscaping() {
        #expect(svc.toBodyHTML("A & B").contains("&amp;"))
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
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<table"))
        #expect(html.contains("<th>Name</th>"))
        #expect(html.contains("<th>Value</th>"))
        #expect(html.contains("<td>A</td>"))
    }

    @Test("日本語ヘッダ行が thead/th にレンダリングされること")
    func japaneseTableHeaderRendering() {
        let md = """
        | メンバー | 6月単価 | 備考 |
        |---|---|---|
        | A | 500,000 | シニアエンジニア想定 |
        """
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<thead>"))
        #expect(html.contains("<th>メンバー</th>"))
        #expect(html.contains("<th>6月単価</th>"))
        #expect(html.contains("<th>備考</th>"))
        #expect(html.contains("<td>A</td>"))
    }

    @Test("4列テーブルのヘッダが正しくレンダリングされること")
    func fourColumnTableHeaderRendering() {
        let md = """
        | ym | A | B | C |
        |---|---|---|---|
        | 2026-02 | 80 | 100 | - |
        """
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<th>ym</th>"))
        #expect(html.contains("<th>A</th>"))
        #expect(html.contains("<th>B</th>"))
        #expect(html.contains("<th>C</th>"))
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
        let html = svc.toBodyHTML(md)
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
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<li data-source-line-start="))
    }

    @Test("通常リストの li に data-source-line-start 属性が付くこと")
    func listItemHasSourceLineAttr() {
        let md = "- item1\n- item2"
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<li data-source-line-start="))
    }

    // MARK: - data-source-line-* 属性（プレビュー同期）

    @Test("h1 に data-source-line-start 属性が付くこと")
    func h1HasSourceLineAttr() {
        let html = svc.toBodyHTML("# Title")
        #expect(html.contains("data-source-line-start=\"1\""))
    }

    @Test("段落に data-source-line-start 属性が付くこと")
    func paragraphHasSourceLineAttr() {
        let html = svc.toBodyHTML("Hello world")
        #expect(html.contains("data-source-line-start=\"1\""))
    }

    @Test("コードブロックに data-source-line-start 属性が付くこと")
    func codeBlockHasSourceLineAttr() {
        let html = svc.toBodyHTML("```swift\nlet x = 1\n```")
        #expect(html.contains("<pre data-source-line-start="))
    }

    @Test("blockquote に data-source-line-start 属性が付くこと")
    func blockquoteHasSourceLineAttr() {
        let html = svc.toBodyHTML("> quote")
        #expect(html.contains("<blockquote data-source-line-start="))
    }

    @Test("テーブルに data-source-line-start 属性が付くこと")
    func tableHasSourceLineAttr() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<table data-source-line-start="))
    }

    @Test("テーブル行（tr）に data-source-line-start 属性が付くこと")
    func tableRowHasSourceLineAttr() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<tr data-source-line-start="))
    }

    @Test("複数ブロックの source-line が正しい行番号になること")
    func multiBlockSourceLines() {
        let md = "# Heading\n\nParagraph"
        let html = svc.toBodyHTML(md)
        // 見出しは1行目、空行を挟んで段落は3行目
        #expect(html.contains("data-source-line-start=\"1\""))
        #expect(html.contains("data-source-line-start=\"3\""))
    }

    @Test("テーブル本文行の source-line が連番になること")
    func tableBodyRowSourceLines() {
        let md = "| H |\n|---|\n| R1 |\n| R2 |"
        let html = svc.toBodyHTML(md)
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
        let html = svc.toBodyHTML(md)
        #expect(html.contains("data-source-line-end="))
        // end >= start の検証: start="1" end="1" のような対応
        #expect(html.contains("data-source-line-start=\"1\" data-source-line-end=\"1\""))
    }
}
