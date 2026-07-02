import Foundation

// MARK: - HTMLSanitizer
//
// rawHTML パススルー（InlineHTML / HTMLBlock）に対する許可リストサニタイズ。
//
// 設計選択: 軽量トークナイザー（独自スキャナー）
//
//   XMLParser (SAX) を最初に試みたが、HTML 固有の void 要素（<br>/<img> 等の
//   非自己閉じ）・エンティティ・文書断片などで XMLParser がパースエラーを起こし
//   全体を escapeAll にフォールバックする問題が発覚（テストで確認）。
//
//   代替として文字列スキャンベースの軽量トークナイザーを採用:
//   - タグ開き（<tag attrs>）・タグ閉じ（</tag>）・テキストの3種類に分解
//   - 属性は NSRegularExpression で key="value" 形式を抽出（大文字小文字非依存）
//   - 壊れた断片（unclosed angle bracket 等）は安全側: 残りを全エスケープ
//
// 脅威モデル（KMD-242):
//   - <script>alert(1)</script>                → script タグごと除去
//   - <img src=x onerror=alert(1)>             → onerror 属性除去、img タグ自体は保持
//   - <iframe src=...>                         → iframe タグごと除去
//   - style="expression(...)"                  → style 属性除去
//   - <SCRIPT> 大文字                          → タグ名は lowercased() で正規化
//   - on* 属性全般                             → allowedAttributes に含まれないため除去
//   - `<img onerror=alert(1)>` 引用符なし      → トークナイザーが引用符なし属性も処理
//
// 正当な利用（保持される):
//   - <details><summary>折りたたみ</summary>...</details>
//   - <table><thead><tr><th>...</th></tr></thead><tbody>...</tbody></table>
//   - <br> <hr> <sup> <sub> <mark> <kbd>
//   - a href/img src は sanitizedLinkURL / sanitizedImageURL で URL 検証済み

final class HTMLSanitizer {

    // MARK: - 許可タグ

    static let allowedTags: Set<String> = [
        // 構造
        "div", "span", "p", "br", "hr",
        // 見出し
        "h1", "h2", "h3", "h4", "h5", "h6",
        // テキスト修飾
        "strong", "em", "b", "i", "u", "s", "del", "ins",
        "code", "pre", "kbd", "mark", "sup", "sub",
        // ブロック
        "blockquote",
        // リスト
        "ul", "ol", "li",
        // テーブル
        "table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption",
        // リンク/メディア
        "a", "img",
        // 折りたたみ
        "details", "summary",
    ]

    // void 要素（終了タグなし）
    private static let voidTags: Set<String> = ["br", "hr", "img", "input", "meta", "link"]

    // MARK: - 許可属性（タグ非依存）

    static let allowedAttributes: Set<String> = [
        "id", "class", "title", "alt",
        // テーブル
        "colspan", "rowspan",
        // href/src は別途 URL 検証
        "href", "src",
        // checkbox 対応
        "type", "checked", "disabled",
    ]

    // 内容ごと除去するタグ（テキストも出力しない）
    static let contentKillerTags: Set<String> = [
        "script", "style", "iframe", "object", "embed", "form",
        "meta", "link", "base", "noscript", "template",
    ]

    static func isContentKillerTag(_ tagName: String) -> Bool {
        contentKillerTags.contains(tagName.lowercased())
    }

    // MARK: - Public API

    /// HTML 文字列を許可リストでサニタイズして返す。
    static func sanitize(_ html: String) -> String {
        var result = ""
        var idx = html.startIndex
        // contentKillerTags の中にいるとき、その終了タグが来るまで出力を抑制する
        var suppressStack: [String] = []

        while idx < html.endIndex {
            // '<' を探す
            guard let ltIdx = html[idx...].firstIndex(of: "<") else {
                // 残りはテキスト
                if suppressStack.isEmpty {
                    result += escapeText(String(html[idx...]))
                }
                break
            }

            // '<' より前はテキスト
            if ltIdx > idx, suppressStack.isEmpty {
                result += escapeText(String(html[idx..<ltIdx]))
            }

            // '<' から '>' を探す
            guard let gtIdx = html[ltIdx...].firstIndex(of: ">") else {
                // '>' がない → 残りを全エスケープして終了（suppressStack 無視: 断片なので安全側）
                if suppressStack.isEmpty {
                    result += escapeText(String(html[ltIdx...]))
                }
                break
            }

            let tagContent = String(html[html.index(after: ltIdx)..<gtIdx])
            let tagStr = processTagWithSuppress(tagContent, suppressStack: &suppressStack)
            if suppressStack.isEmpty {
                result += tagStr
            }
            idx = html.index(after: gtIdx)
        }

        return result
    }

    /// suppressStack を更新しながらタグを処理する。
    private static func processTagWithSuppress(_ content: String, suppressStack: inout [String]) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespaces)

        // 終了タグ
        if trimmed.hasPrefix("/") {
            let tagName = trimmed.dropFirst()
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .components(separatedBy: .whitespaces).first ?? ""

            if !suppressStack.isEmpty, suppressStack.last == tagName {
                suppressStack.removeLast()
                return "" // contentKillerTag の終了タグは出力しない
            }
            if suppressStack.isEmpty {
                return processTag(content)
            }
            return ""
        }

        // 開始タグ
        let tagName = tagNameFrom(trimmed)
        if contentKillerTags.contains(tagName) {
            // self-closing でなければ suppress スタックに積む
            if !trimmed.hasSuffix("/") {
                suppressStack.append(tagName)
            }
            return "" // contentKillerTag は出力しない
        }

        if suppressStack.isEmpty {
            return processTag(content)
        }
        return ""
    }

    private static func tagNameFrom(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let spaceIdx = trimmed.firstIndex(of: " ") {
            return String(trimmed[..<spaceIdx]).lowercased()
        }
        return trimmed.lowercased()
    }

    // MARK: - タグ処理

    private static func processTag(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespaces)

        // HTML コメント <!-- ... --> はスキップ
        if trimmed.hasPrefix("!--") { return "" }
        // DOCTYPE はスキップ
        if trimmed.lowercased().hasPrefix("!doctype") { return "" }
        // 処理命令はスキップ
        if trimmed.hasPrefix("?") { return "" }

        // 終了タグ
        if trimmed.hasPrefix("/") {
            let tagName = trimmed.dropFirst()
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .components(separatedBy: .whitespaces).first ?? ""
            guard allowedTags.contains(tagName), !voidTags.contains(tagName) else {
                return ""
            }
            return "</\(tagName)>"
        }

        // 開始タグ（または void 要素）
        // タグ名と属性部分を分割
        let parts = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let tagName: String
        let attrsStr: String

        if let spaceIdx = parts.firstIndex(of: " ") {
            tagName = String(parts[..<spaceIdx]).lowercased()
            attrsStr = String(parts[parts.index(after: spaceIdx)...])
        } else {
            tagName = parts.lowercased()
            attrsStr = ""
        }

        guard allowedTags.contains(tagName) else {
            return "" // 許可されていないタグは除去
        }

        let safeAttrs = sanitizeAttributes(attrsStr, tagName: tagName)
        let attrStr = safeAttrs.isEmpty ? "" : " \(safeAttrs)"

        if voidTags.contains(tagName) {
            return "<\(tagName)\(attrStr)>"
        }
        return "<\(tagName)\(attrStr)>"
    }

    // MARK: - 属性サニタイズ

    /// 属性文字列から許可属性のみを抽出して再構築する。
    /// 形式: `key="value"`, `key='value'`, `key=value`, `key`（boolean）に対応。
    private static func sanitizeAttributes(_ attrsStr: String, tagName: String) -> String {
        guard !attrsStr.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }

        var safeAttrs: [(String, String)] = []
        var scanner = AttributeScanner(attrsStr)

        while let (key, value) = scanner.nextAttribute() {
            let normalKey = key.lowercased()
            // on* 属性・style 属性は除去
            if normalKey.hasPrefix("on") || normalKey == "style" { continue }
            guard allowedAttributes.contains(normalKey) else { continue }

            // URL 属性の検証
            var safeValue = value
            if normalKey == "href" {
                safeValue = sanitizedLinkURL(value)
            } else if normalKey == "src" {
                safeValue = sanitizedImageURL(value)
            }

            safeAttrs.append((normalKey, safeValue))
        }

        return safeAttrs.map { (k, v) in "\(k)=\"\(escapeAttr(v))\"" }.joined(separator: " ")
    }

    // MARK: - Helpers

    static func escapeAll(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func escapeAttr(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func escapeText(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - URL 許可リスト（MarkdownService と同等ロジック）

    static func sanitizedLinkURL(_ url: String) -> String {
        let stripped = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.drop(while: { $0.value < 0x20 })
        let decoded = String(stripped).removingPercentEncoding ?? String(stripped)
        let normalized = decoded.lowercased()
        let allowed = ["http://", "https://", "mailto:", "#", "/", "./", "../"]
        for prefix in allowed where normalized.hasPrefix(prefix) {
            return stripped.isEmpty ? "#" : String(stripped)
        }
        if !normalized.contains(":") {
            return stripped.isEmpty ? "#" : String(stripped)
        }
        return "#"
    }

    static func sanitizedImageURL(_ url: String) -> String {
        let stripped = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.drop(while: { $0.value < 0x20 })
        let decoded = String(stripped).removingPercentEncoding ?? String(stripped)
        let normalized = decoded.lowercased()
        let allowed = ["http://", "https://", "data:image/", "/", "./", "../"]
        for prefix in allowed where normalized.hasPrefix(prefix) {
            return stripped.isEmpty ? "" : String(stripped)
        }
        if !normalized.contains(":") {
            return stripped.isEmpty ? "" : String(stripped)
        }
        return ""
    }
}

// MARK: - AttributeScanner
//
// 属性文字列 `key="value" key2='value2' key3=value3 boolkey` を順次スキャンする。
// HTML の属性パース仕様に準拠しつつ、悪意あるバイパス（空白偽装等）にも対応。

private struct AttributeScanner {
    private let source: String
    private var idx: String.Index

    init(_ source: String) {
        self.source = source
        self.idx = source.startIndex
    }

    mutating func nextAttribute() -> (String, String)? {
        // 先頭空白をスキップ
        skipWhitespace()
        guard idx < source.endIndex else { return nil }

        // キー読み取り（= か空白か終端まで）
        let keyStart = idx
        while idx < source.endIndex, source[idx] != "=", !source[idx].isWhitespace, source[idx] != ">" {
            idx = source.index(after: idx)
        }
        let key = String(source[keyStart..<idx])
        guard !key.isEmpty else {
            // 読み進む（無限ループ防止）
            if idx < source.endIndex { idx = source.index(after: idx) }
            return nil
        }

        skipWhitespace()

        // "=" があれば値を読む
        guard idx < source.endIndex, source[idx] == "=" else {
            // boolean 属性（値なし）
            return (key, "")
        }
        idx = source.index(after: idx) // "=" をスキップ
        skipWhitespace()

        guard idx < source.endIndex else {
            return (key, "")
        }

        let value: String
        if source[idx] == "\"" || source[idx] == "'" {
            // 引用符あり
            let quote = source[idx]
            idx = source.index(after: idx)
            let valueStart = idx
            while idx < source.endIndex, source[idx] != quote {
                idx = source.index(after: idx)
            }
            value = String(source[valueStart..<idx])
            if idx < source.endIndex { idx = source.index(after: idx) } // 閉じ引用符をスキップ
        } else {
            // 引用符なし（空白 or > まで）
            let valueStart = idx
            while idx < source.endIndex, !source[idx].isWhitespace, source[idx] != ">" {
                idx = source.index(after: idx)
            }
            value = String(source[valueStart..<idx])
        }

        return (key, value)
    }

    private mutating func skipWhitespace() {
        while idx < source.endIndex, source[idx].isWhitespace {
            idx = source.index(after: idx)
        }
    }
}
