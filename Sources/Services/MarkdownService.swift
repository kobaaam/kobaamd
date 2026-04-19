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
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
            *{box-sizing:border-box}
            html{background:#fdfcf8}
            body{
              font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;
              font-size:15px;
              line-height:1.75;
              color:#1a1a1a;
              max-width:720px;
              margin:0 auto;
              padding:32px 28px 80px;
              background:#fdfcf8;
              -webkit-font-smoothing:antialiased;
            }
            h1,h2,h3,h4,h5,h6{
              font-weight:700;
              line-height:1.3;
              margin:1.6em 0 0.5em;
              color:#111;
            }
            h1{font-size:2em;margin-top:0.8em}
            h2{font-size:1.4em;border-bottom:2px solid #e8e5df;padding-bottom:0.25em}
            h3{font-size:1.15em}
            p{margin:0.8em 0}
            a{color:#0070f3;text-decoration:none}
            a:hover{text-decoration:underline}
            strong{font-weight:700}
            em{font-style:italic}
            del{color:#999}
            code{
              font-family:"SF Mono",Menlo,Monaco,monospace;
              font-size:0.88em;
              background:#eeecea;
              padding:2px 5px;
              border-radius:4px;
              color:#c0392b;
            }
            pre{
              background:#f0ede8;
              border:1px solid #e0ddd8;
              border-radius:8px;
              padding:16px 20px;
              overflow-x:auto;
              margin:1.2em 0;
            }
            pre code{
              background:none;
              padding:0;
              color:#1a1a1a;
              font-size:0.87em;
            }
            blockquote{
              border-left:3px solid #FF5B1F;
              margin:1em 0;
              padding:4px 0 4px 18px;
              color:#555;
              font-style:italic;
            }
            img{max-width:100%;border-radius:6px}
            hr{border:none;border-top:1px solid #e0ddd8;margin:2em 0}
            table{border-collapse:collapse;width:100%;margin:1.2em 0;font-size:0.93em}
            th,td{border:1px solid #e0ddd8;padding:8px 14px;text-align:left}
            th{background:#f5f2ec;font-weight:600}
            tr:nth-child(even) td{background:#faf8f4}
            ul,ol{padding-left:1.6em;margin:0.8em 0}
            li{margin:0.25em 0}
            li input[type=checkbox]{margin-right:6px;accent-color:#FF5B1F}
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
        case is Markdown.Document:
            return renderChildren(of: markup)
        case let heading as Heading:
            let level = min(max(heading.level, 1), 6)
            return "<h\(level)>\(renderChildren(of: heading))</h\(level)>"
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
        case let strikethrough as Strikethrough:
            return "<del>\(renderChildren(of: strikethrough))</del>"
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
        case let item as ListItem where item.checkbox != nil:
            let checked = item.checkbox == .checked ? "checked" : ""
            return "<li><input type=\"checkbox\" \(checked) disabled> \(renderChildren(of: item))</li>"
        case let item as ListItem:
            return "<li>\(renderChildren(of: item))</li>"
        case let blockquote as BlockQuote:
            return "<blockquote>\(renderChildren(of: blockquote))</blockquote>"
        case is ThematicBreak:
            return "<hr>"
        case let table as Table:
            return renderTable(table)
        case let inlineHTML as InlineHTML:
            return inlineHTML.rawHTML
        case let htmlBlock as HTMLBlock:
            return htmlBlock.rawHTML
        default:
            return renderChildren(of: markup)
        }
    }

    private func renderTable(_ table: Table) -> String {
        var html = "<table>"
        for child in table.children {
            if let head = child as? Table.Head {
                html += "<thead><tr>"
                for row in head.children.compactMap({ $0 as? Table.Row }) {
                    for cell in row.children.compactMap({ $0 as? Table.Cell }) {
                        html += "<th>\(renderChildren(of: cell))</th>"
                    }
                }
                html += "</tr></thead>"
            } else if let body = child as? Table.Body {
                html += "<tbody>"
                for row in body.children.compactMap({ $0 as? Table.Row }) {
                    html += "<tr>"
                    for cell in row.children.compactMap({ $0 as? Table.Cell }) {
                        html += "<td>\(renderChildren(of: cell))</td>"
                    }
                    html += "</tr>"
                }
                html += "</tbody>"
            }
        }
        html += "</table>"
        return html
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
