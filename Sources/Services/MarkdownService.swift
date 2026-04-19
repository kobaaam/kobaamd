import Foundation
import Markdown

final class MarkdownService {
    func toHTML(_ text: String) -> String {
        let document = Markdown.Document(parsing: text)
        let bodyContent = renderChildren(of: document)
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
            body{font-family:-apple-system,sans-serif;max-width:800px;margin:40px auto;padding:0 20px;line-height:1.6}
            code{background:#f0f0f0;padding:2px 4px;border-radius:3px;font-family:monospace}
            pre{background:#f0f0f0;padding:16px;border-radius:6px;overflow-x:auto}
            pre code{background:none;padding:0}
            blockquote{border-left:4px solid #ddd;padding-left:16px;color:#666;margin:0}
            img{max-width:100%}
            hr{border:none;border-top:1px solid #ddd;margin:24px 0}
            </style>
        </head>
        <body>
        \(bodyContent)
        </body>
        </html>
        """
    }

    private func render(_ markup: Markup) -> String {
        switch markup {
        case let heading as Heading:
            let level = min(max(heading.level, 1), 6)
            return "<h\(level)>\(renderChildren(of: heading))</h\(level)>"
        case is Markdown.Document:
            return renderChildren(of: markup)
        case let paragraph as Paragraph:
            return "<p>\(renderChildren(of: paragraph))</p>"
        case let text as Text:
            return escapeHTML(text.string)
        case is SoftBreak:
            return "\n"
        case is LineBreak:
            return "<br>"
        case let strong as Strong:
            return "<strong>\(renderChildren(of: strong))</strong>"
        case let emphasis as Emphasis:
            return "<em>\(renderChildren(of: emphasis))</em>"
        case let code as InlineCode:
            return "<code>\(escapeHTML(code.code))</code>"
        case let codeBlock as CodeBlock:
            let langAttr = codeBlock.language.map { " class=\"language-\(escapeAttr($0))\"" } ?? ""
            return "<pre><code\(langAttr)>\(escapeHTML(codeBlock.code))</code></pre>"
        case let link as Link:
            let dest = escapeAttr(link.destination ?? "")
            return "<a href=\"\(dest)\">\(renderChildren(of: link))</a>"
        case let image as Image:
            let src = escapeAttr(image.source ?? "")
            let alt = escapeHTML(image.plainText)
            return "<img src=\"\(src)\" alt=\"\(alt)\">"
        case let list as UnorderedList:
            return "<ul>\(renderChildren(of: list))</ul>"
        case let list as OrderedList:
            return "<ol>\(renderChildren(of: list))</ol>"
        case let item as ListItem:
            return "<li>\(renderChildren(of: item))</li>"
        case let blockquote as BlockQuote:
            return "<blockquote>\(renderChildren(of: blockquote))</blockquote>"
        case is ThematicBreak:
            return "<hr>"
        case let inlineHTML as InlineHTML:
            return inlineHTML.rawHTML
        case let htmlBlock as HTMLBlock:
            return htmlBlock.rawHTML
        default:
            return renderChildren(of: markup)
        }
    }

    private func renderChildren(of markup: Markup) -> String {
        markup.children.map { render($0) }.joined()
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttr(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
