import Foundation
import Markdown

final class MarkdownService {

    // MARK: - Shell head cache (perf probe finding)
    //
    // mermaid.min.js (3 MB) を含む HTML head 部分の文字列補間が cold start で
    // ~8 秒かかり loading 表示の主因になっていた。head のうち変動するのは
    // theme.previewCSS のみなので、theme ごとにテンプレートをキャッシュして再利用する。
    //
    // KMD-242: nonce 対応のためキャッシュはテンプレート（nonce プレースホルダー入り）を
    // 保持し、loadHTMLString 呼び出しごとに新しい nonce を差し込む。
    // nonce 自体はキャッシュキーに含めない。
    private static var shellHeadTemplateCache: [String: String] = [:]
    private static let shellHeadLock = NSLock()
    /// シェル HTML の構造変更時にインクリメントしてキャッシュを無効化する。
    private static let shellHeadRevision = 4

    /// nonce の placeholder。キャッシュされたテンプレート内に埋め込み、
    /// 呼び出し時に実際の nonce 値で置換する。
    private static let noncePlaceholder = "{{NONCE}}"

    // MARK: - Nonce 生成

    /// ロードごとにランダムな nonce（Base64 エンコード、16 バイト）を生成する。
    static func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Shell head テンプレート構築（キャッシュ）

    private static func shellHeadTemplate(themeKey: String, previewCSS: String) -> String {
        let cacheKey = "\(themeKey)-r\(shellHeadRevision)"
        shellHeadLock.lock()
        if let cached = shellHeadTemplateCache[cacheKey] {
            shellHeadLock.unlock()
            return cached
        }
        shellHeadLock.unlock()

        PerfLogger.begin("MarkdownService.shellHeadTemplate.build(theme=\(themeKey))")

        // KMD-242: script-src 'unsafe-inline' を廃止し 'nonce-{{NONCE}}' に変更。
        // inline script タグすべてに nonce="{{NONCE}}" を付与する。
        // mermaid バンドル (inline <script nonce=...>) も対象。
        // callAsyncJavaScript / evaluateJavaScript は WKWebView の user script 扱いで
        // ページ CSP の影響を受けないためスクロール同期等は引き続き動作する（PR #167 確認済み）。
        let mermaidScript = BundledJS.mermaid.isEmpty
            ? "<script src=\"https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js\" nonce=\"\(noncePlaceholder)\"></script>"
            : "<script nonce=\"\(noncePlaceholder)\">\(BundledJS.mermaid)</script>"
        let csp = "default-src 'none'; script-src 'nonce-\(noncePlaceholder)'; style-src 'unsafe-inline'; img-src http: https: data:; connect-src 'none'"
        let template = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="\(csp)">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            \(mermaidScript)
            <script nonce="\(noncePlaceholder)">
            document.addEventListener('DOMContentLoaded', function() {
              document.querySelectorAll('pre > code.language-mermaid').forEach(function(el) {
                var div = document.createElement('div');
                div.className = 'mermaid';
                div.textContent = el.textContent;
                el.parentNode.replaceWith(div);
              });
              if (typeof mermaid !== 'undefined') {
                mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'strict' });
                mermaid.run({ querySelector: '.mermaid' });
              }
            });
            document.addEventListener('click', function(e) {
              if (e.target.closest('a')) return;
              var el = e.target.closest('[data-source-line-start]');
              if (!el) return;
              var line = parseInt(el.dataset.sourceLineStart, 10);
              if (!line || !window.webkit || !window.webkit.messageHandlers.previewLineSelected) return;
              window.webkit.messageHandlers.previewLineSelected.postMessage({ line: line });
            });
            </script>
            <style>
            \(previewCSS)
            </style>
        </head>
        <body>

        """
        PerfLogger.end("MarkdownService.shellHeadTemplate.build(theme=\(themeKey))")

        shellHeadLock.lock()
        shellHeadTemplateCache[cacheKey] = template
        shellHeadLock.unlock()
        return template
    }

    /// ロードごとに新しい nonce を差し込んだ shell head を返す。
    private static func shellHead(themeKey: String, previewCSS: String) -> String {
        let template = shellHeadTemplate(themeKey: themeKey, previewCSS: previewCSS)
        let nonce = generateNonce()
        return template.replacingOccurrences(of: noncePlaceholder, with: nonce)
    }

    /// ボディのコンテンツだけ返す（WKWebView の差分更新用）。
    func toBodyHTML(_ text: String) -> String {
        PerfLogger.begin("MarkdownService.toBodyHTML(\(text.count))")
        defer { PerfLogger.end("MarkdownService.toBodyHTML(\(text.count))") }
        let document = Markdown.Document(parsing: text)
        return renderChildren(of: document)
    }

    /// 初回ロード用のフル HTML（シェル＋スタイル＋mermaid.js 込み）。
    /// `body` を渡すと markdown 再パースをスキップする。
    func toHTML(_ text: String, body: String? = nil) -> String {
        PerfLogger.begin("MarkdownService.toHTML(\(text.count) body=\(body == nil ? "nil" : "given"))")
        defer { PerfLogger.end("MarkdownService.toHTML(\(text.count) body=\(body == nil ? "nil" : "given"))") }
        let bodyContent: String
        if let body {
            bodyContent = body
        } else {
            let document = Markdown.Document(parsing: text)
            bodyContent = renderChildren(of: document)
        }
        let theme = AppState.shared.selectedTheme
        let head = Self.shellHead(themeKey: theme.rawValue, previewCSS: theme.previewCSS)
        return head + bodyContent + "\n</body>\n</html>"
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
            let dest = sanitizedLinkURL(link.destination ?? "")
            return "<a href=\"\(escapeAttr(dest))\">\(renderChildren(of: link))</a>"
        case let image as Image:
            let src = sanitizedImageURL(image.source ?? "")
            let alt = escapeHTML(image.plainText)
            return "<img src=\"\(escapeAttr(src))\" alt=\"\(alt)\">"
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
            // KMD-242: rawHTML 許可リストサニタイズ。on* 属性・script/iframe 等を除去。
            return HTMLSanitizer.sanitize(inlineHTML.rawHTML)
        case let htmlBlock as HTMLBlock:
            // KMD-242: 同上
            return HTMLSanitizer.sanitize(htmlBlock.rawHTML)
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
        let headerRowCount = table.children
            .compactMap { $0 as? Table.Head }
            .map(tableHeadRowCount(in:))
            .reduce(0, +)

        var html = "<table\(srcAttr(table))>"

        for child in table.children {
            if let head = child as? Table.Head {
                html += "<thead>"
                var offset = 0
                for rowMarkup in tableHeadRowMarkups(in: head) {
                    let attr = tableRowAttr(rowMarkup, tableStart: tableStart, offset: offset)
                    html += "<tr\(attr)>"
                    for cell in tableRowCells(in: rowMarkup) {
                        html += "<th>\(renderChildren(of: cell))</th>"
                    }
                    html += "</tr>"
                    offset += 1
                }
                html += "</thead>"
            } else if let body = child as? Table.Body {
                html += "<tbody>"
                // ヘッダ行数 + セパレータ行(1行) 分をオフセット
                var offset = headerRowCount + 1
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

    /// swift-markdown 0.4+ では `Table.Head` の子が `Table.Row` ではなく `Table.Cell` 直結のことがある。
    private func tableHeadRowMarkups(in head: Table.Head) -> [Markup] {
        let rows = head.children.compactMap { $0 as? Table.Row }
        if !rows.isEmpty { return rows }
        let cells = head.children.compactMap { $0 as? Table.Cell }
        return cells.isEmpty ? [] : [head]
    }

    private func tableHeadRowCount(in head: Table.Head) -> Int {
        let rows = head.children.compactMap { $0 as? Table.Row }
        if !rows.isEmpty { return rows.count }
        return head.children.contains(where: { $0 is Table.Cell }) ? 1 : 0
    }

    private func tableRowCells(in rowMarkup: Markup) -> [Table.Cell] {
        if let row = rowMarkup as? Table.Row {
            return row.children.compactMap { $0 as? Table.Cell }
        }
        if let head = rowMarkup as? Table.Head {
            return head.children.compactMap { $0 as? Table.Cell }
        }
        return []
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
        // KMD-242: InlineHTML を含む場合は suppress フィルタを適用する。
        // swift-markdown は <script>text</script> を3ノード（InlineHTML, Text, InlineHTML）に
        // 分解するため、テキストノードも suppress 範囲内では出力を抑制する。
        let children = Array(markup.children)
        let hasInlineHTML = children.contains { $0 is InlineHTML }
        if hasInlineHTML {
            return renderChildrenWithSuppression(children)
        }
        return children.map { render($0) }.joined()
    }

    /// InlineHTML の contentKillerTag 開始/終了タグをステートとして追跡し、
    /// suppress 状態中のノードを出力しない。
    private func renderChildrenWithSuppression(_ children: [Markup]) -> String {
        var result = ""
        var suppressStack: [String] = []

        for child in children {
            if let inlineHTML = child as? InlineHTML {
                let raw = inlineHTML.rawHTML.trimmingCharacters(in: .whitespaces)
                // 終了タグ判定: </tagname>
                if raw.hasPrefix("</") {
                    let tagName = raw.dropFirst(2)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "> \t"))
                        .lowercased()
                        .components(separatedBy: .whitespaces).first ?? ""
                    if !suppressStack.isEmpty, suppressStack.last == tagName {
                        suppressStack.removeLast()
                    }
                    // suppress 中でも suppress 解除後でも終了タグは出力しない（sanitize 経由で決まる）
                    if suppressStack.isEmpty {
                        result += HTMLSanitizer.sanitize(inlineHTML.rawHTML)
                    }
                    continue
                }
                // 開始タグ判定
                let sanitized = HTMLSanitizer.sanitize(inlineHTML.rawHTML)
                // contentKillerTag なら suppress スタックに積む
                let tagName = extractTagName(raw)
                if HTMLSanitizer.isContentKillerTag(tagName) && !raw.hasSuffix("/>") && !raw.hasSuffix("/ >") {
                    suppressStack.append(tagName)
                    // タグ自体も出力しない
                } else if suppressStack.isEmpty {
                    result += sanitized
                }
            } else if suppressStack.isEmpty {
                result += render(child)
            }
            // suppress 状態中は出力しない
        }

        return result
    }

    /// "<tag attrs>" から tag 名を抽出する（< > は除去済みの文字列を受け取る）
    private func extractTagName(_ tagContent: String) -> String {
        let trimmed = tagContent
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        if let spaceIdx = trimmed.firstIndex(of: " ") {
            return String(trimmed[..<spaceIdx]).lowercased()
        }
        return trimmed.lowercased()
    }

    /// リンク href に許可するスキーム: http/https/mailto/# アンカー/相対パス
    /// 大文字小文字・先頭空白・制御文字・percent-encoding での偽装にも対応する。
    /// 許可スキーム以外（javascript: 等）は "#" に無害化する。
    private func sanitizedLinkURL(_ url: String) -> String {
        // 先頭の空白・制御文字を除去して小文字でスキームを判定する
        let stripped = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .drop(while: { $0.value < 0x20 }) // 制御文字除去
        // percent-encoding バイパス対策: %6a%61%76%61%73%63%72%69%70%74%3a... = javascript:
        let decoded = String(stripped).removingPercentEncoding ?? String(stripped)
        let normalized = decoded.lowercased()
        let allowedPrefixes = ["http://", "https://", "mailto:", "#", "/", "./", "../"]
        for prefix in allowedPrefixes where normalized.hasPrefix(prefix) {
            return stripped.isEmpty ? "#" : String(stripped)
        }
        // スキームを含まない相対パスも許可（scheme-less で : が無いもの）
        if !normalized.contains(":") {
            return stripped.isEmpty ? "#" : String(stripped)
        }
        return "#"
    }

    /// 画像 src に許可するスキーム: http/https/data:image/相対パス
    /// javascript: data:text/html 等は無害化する。percent-encoding バイパスにも対応。
    private func sanitizedImageURL(_ url: String) -> String {
        let stripped = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .drop(while: { $0.value < 0x20 })
        // percent-encoding バイパス対策
        let decoded = String(stripped).removingPercentEncoding ?? String(stripped)
        let normalized = decoded.lowercased()
        let allowedPrefixes = ["http://", "https://", "data:image/", "/", "./", "../"]
        for prefix in allowedPrefixes where normalized.hasPrefix(prefix) {
            return stripped.isEmpty ? "" : String(stripped)
        }
        if !normalized.contains(":") {
            return stripped.isEmpty ? "" : String(stripped)
        }
        return ""
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
