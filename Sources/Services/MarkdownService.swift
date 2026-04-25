import Foundation
import Markdown

final class MarkdownService {

    /// ボディのコンテンツだけ返す（WKWebView の差分更新用）。
    func toBodyHTML(_ text: String) -> String {
        let document = Markdown.Document(parsing: text)
        return renderChildren(of: document)
    }

    /// 初回ロード用のフル HTML（シェル＋スタイル＋mermaid.js 込み）。
    func toHTML(_ text: String) -> String {
        let document = Markdown.Document(parsing: text)
        let bodyContent = renderChildren(of: document)
        // Inline the bundled mermaid.min.js so preview works offline.
        // BundledJS.mermaid is empty only if the resource is missing (build error).
        let mermaidScript = BundledJS.mermaid.isEmpty
            ? "<script src=\"https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js\"></script>"
            : "<script>\(BundledJS.mermaid)</script>"
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            \(mermaidScript)
            <script>
            document.addEventListener('DOMContentLoaded', function() {
              // Convert <pre><code class="language-mermaid"> to <div class="mermaid">
              document.querySelectorAll('pre > code.language-mermaid').forEach(function(el) {
                var div = document.createElement('div');
                div.className = 'mermaid';
                div.textContent = el.textContent;
                el.parentNode.replaceWith(div);
              });
              if (typeof mermaid !== 'undefined') {
                mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'loose' });
                mermaid.run({ querySelector: '.mermaid' });
              }
            });
            </script>
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
            li{margin:0}
            li p{margin:0}
            li:has(input[type=checkbox]){list-style:none;margin-left:-1.6em}
            li input[type=checkbox]{margin-right:6px;accent-color:#FF5B1F;vertical-align:middle}
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
            return "<h\(level)\(srcAttr(heading))>\(renderChildren(of: heading))</h\(level)>"
        case let paragraph as Paragraph:
            return "<p\(srcAttr(paragraph))>\(renderChildren(of: paragraph))</p>"
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
            return "<pre\(srcAttr(codeBlock))><code\(langAttr)>\(escapeHTML(codeBlock.code))</code></pre>"
        case let link as Link:
            let dest = escapeAttr(link.destination ?? "")
            return "<a href=\"\(dest)\">\(renderChildren(of: link))</a>"
        case let image as Image:
            let src = escapeAttr(image.source ?? "")
            let alt = escapeHTML(image.plainText)
            return "<img src=\"\(src)\" alt=\"\(alt)\">"
        case let list as UnorderedList:
            return "<ul\(srcAttr(list))>\(renderChildren(of: list))</ul>"
        case let list as OrderedList:
            return "<ol\(srcAttr(list))>\(renderChildren(of: list))</ol>"
        case let item as ListItem where item.checkbox != nil:
            let checked = item.checkbox == .checked ? "checked" : ""
            let inlineContent = item.children.compactMap { child -> String? in
                if let para = child as? Paragraph {
                    return renderChildren(of: para)
                }
                return render(child)
            }.joined()
            return "<li\(srcAttr(item))><input type=\"checkbox\" \(checked) disabled> \(inlineContent)</li>"
        case let item as ListItem:
            return "<li\(srcAttr(item))>\(renderChildren(of: item))</li>"
        case let blockquote as BlockQuote:
            return "<blockquote\(srcAttr(blockquote))>\(renderChildren(of: blockquote))</blockquote>"
        case let thematicBreak as ThematicBreak:
            return "<hr\(srcAttr(thematicBreak))>"
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

    /// ASTノードのソース範囲を HTML 属性として返す（プレビュー同期用）
    private func srcAttr(_ markup: Markup) -> String {
        guard let r = markup.range else { return "" }
        return " data-source-line-start=\"\(r.lowerBound.line)\" data-source-line-end=\"\(r.upperBound.line)\""
    }

    private func renderTable(_ table: Table) -> String {
        // Markdown テーブルは 1行/row のため、Table.Row.range が nil の場合は
        // テーブル開始行 + 行オフセットで行番号を手動計算する
        let tableStart = table.range?.lowerBound.line ?? 0
        let headRows = table.children.compactMap { $0 as? Table.Head }
            .flatMap { $0.children.compactMap { $0 as? Table.Row } }

        var html = "<table\(srcAttr(table))>"

        for child in table.children {
            if let head = child as? Table.Head {
                html += "<thead>"
                var offset = 0
                for row in head.children.compactMap({ $0 as? Table.Row }) {
                    let attr = tableRowAttr(row, tableStart: tableStart, offset: offset)
                    html += "<tr\(attr)>"
                    for cell in row.children.compactMap({ $0 as? Table.Cell }) {
                        html += "<th>\(renderChildren(of: cell))</th>"
                    }
                    html += "</tr>"
                    offset += 1
                }
                html += "</thead>"
            } else if let body = child as? Table.Body {
                html += "<tbody>"
                // ヘッダ行数 + セパレータ行(1行) 分をオフセット
                var offset = headRows.count + 1
                for row in body.children.compactMap({ $0 as? Table.Row }) {
                    let attr = tableRowAttr(row, tableStart: tableStart, offset: offset)
                    html += "<tr\(attr)>"
                    for cell in row.children.compactMap({ $0 as? Table.Cell }) {
                        html += "<td>\(renderChildren(of: cell))</td>"
                    }
                    html += "</tr>"
                    offset += 1
                }
                html += "</tbody>"
            }
        }
        html += "</table>"
        return html
    }

    /// Table.Row の行番号属性を返す。range がある場合はそれを優先し、
    /// ない場合はテーブル先頭行 + オフセットで推定する。
    private func tableRowAttr(_ row: Markup, tableStart: Int, offset: Int) -> String {
        if let r = row.range {
            return " data-source-line-start=\"\(r.lowerBound.line)\" data-source-line-end=\"\(r.upperBound.line)\""
        }
        guard tableStart > 0 else { return "" }
        let line = tableStart + offset
        return " data-source-line-start=\"\(line)\" data-source-line-end=\"\(line)\""
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
