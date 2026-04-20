import Testing
@testable import kobaamd

@Suite("MarkdownService")
struct MarkdownServiceTests {
    let svc = MarkdownService()

    // Extract just the <body> content for concise assertions
    private func body(of html: String) -> String {
        guard let start = html.range(of: "<body>"),
              let end = html.range(of: "</body>") else { return html }
        return String(html[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Headings

    @Test("h1 renders correctly")
    func h1Rendering() {
        #expect(body(of: svc.toHTML("# Hello")).contains("<h1>Hello</h1>"))
    }

    @Test("h2 renders correctly")
    func h2Rendering() {
        #expect(body(of: svc.toHTML("## Section")).contains("<h2>Section</h2>"))
    }

    @Test("h3 renders correctly")
    func h3Rendering() {
        #expect(body(of: svc.toHTML("### Sub")).contains("<h3>Sub</h3>"))
    }

    // MARK: - Inline

    @Test("Bold text renders as <strong>")
    func boldRendering() {
        #expect(body(of: svc.toHTML("**bold**")).contains("<strong>bold</strong>"))
    }

    @Test("Italic renders as <em>")
    func italicRendering() {
        #expect(body(of: svc.toHTML("_italic_")).contains("<em>italic</em>"))
    }

    @Test("Strikethrough renders as <del>")
    func strikethroughRendering() {
        #expect(body(of: svc.toHTML("~~del~~")).contains("<del>del</del>"))
    }

    @Test("Inline code renders as <code>")
    func inlineCodeRendering() {
        #expect(body(of: svc.toHTML("`code`")).contains("<code>code</code>"))
    }

    @Test("Link renders with href and text")
    func linkRendering() {
        let html = body(of: svc.toHTML("[text](https://example.com)"))
        #expect(html.contains("href=\"https://example.com\""))
        #expect(html.contains(">text<"))
    }

    // MARK: - Block elements

    @Test("Unordered list renders <ul>")
    func unorderedList() {
        let html = body(of: svc.toHTML("- item1\n- item2"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>"))
    }

    @Test("Ordered list renders <ol>")
    func orderedList() {
        #expect(body(of: svc.toHTML("1. first\n2. second")).contains("<ol>"))
    }

    @Test("Code block renders <pre> with language class")
    func codeBlock() {
        let html = body(of: svc.toHTML("```swift\nlet x = 1\n```"))
        #expect(html.contains("<pre>"))
        #expect(html.contains("language-swift"))
    }

    @Test("Blockquote renders <blockquote>")
    func blockquote() {
        #expect(body(of: svc.toHTML("> quote")).contains("<blockquote>"))
    }

    @Test("Horizontal rule renders <hr>")
    func horizontalRule() {
        #expect(body(of: svc.toHTML("---")).contains("<hr>"))
    }

    // MARK: - HTML escaping (security)

    // NOTE: Markdown spec allows raw HTML blocks to pass through unchanged.
    // MarkdownService deliberately forwards HTMLBlock/InlineHTML as-is.
    // Escaping is applied to TEXT nodes (headings, paragraphs, etc.).

    @Test("< and > in plain text are escaped")
    func anglebracketsInTextAreEscaped() {
        // Plain paragraph text (not raw HTML) — escapeHTML() must apply
        let html = body(of: svc.toHTML("Use <tag> and > literally"))
        #expect(html.contains("&lt;tag&gt;"))
        #expect(html.contains("&gt;"))
    }

    @Test("Heading text with special characters is escaped")
    func headingTextIsEscaped() {
        let html = body(of: svc.toHTML("# A < B & C"))
        #expect(html.contains("<h1>A &lt; B &amp; C</h1>"))
    }

    @Test("Ampersands in text are escaped")
    func ampersandEscaping() {
        #expect(body(of: svc.toHTML("A & B")).contains("&amp;"))
    }

    // MARK: - Document structure

    @Test("Output always contains DOCTYPE")
    func outputContainsDoctype() {
        #expect(svc.toHTML("hello").contains("<!DOCTYPE html>"))
    }

    @Test("Empty input produces valid HTML skeleton")
    func emptyInputProducesValidHTML() {
        let html = svc.toHTML("")
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<body>"))
        #expect(html.contains("</body>"))
    }

    @Test("Mermaid script tag is always included")
    func mermaidScriptPresent() {
        #expect(svc.toHTML("test").contains("mermaid"))
    }

    // MARK: - Table

    @Test("Table renders to table elements")
    func tableRendering() {
        let md = "| Name | Value |\n| --- | --- |\n| A | 1 |"
        let html = body(of: svc.toHTML(md))
        #expect(html.contains("<table>"))
        #expect(html.contains("<td>A</td>"))
        #expect(html.contains("<th>Name</th>") || html.contains("<th>"))
    }

    // MARK: - Mermaid code block

    @Test("Mermaid code block gets language-mermaid class")
    func mermaidBlockHasLanguageClass() {
        let md = "```mermaid\ngraph TD;\nA-->B;\n```"
        let html = svc.toHTML(md)
        #expect(html.contains("language-mermaid"))
    }
}
