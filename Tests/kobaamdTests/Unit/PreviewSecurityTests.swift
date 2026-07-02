import Foundation
import Testing
@testable import kobaamd

@Suite("Preview security hardening")
struct PreviewSecurityTests {

    // MARK: - HTMLSanitizer: 攻撃系（除去確認）

    @Test("<script> タグが除去されること")
    func sanitizerRemovesScriptTag() {
        let result = HTMLSanitizer.sanitize("<script>alert(1)</script>")
        #expect(!result.contains("<script"))
        #expect(!result.contains("alert(1)"))
    }

    @Test("img の onerror 属性が除去され img タグ自体は保持されること")
    func sanitizerRemovesOnerrorKeepsImg() {
        let result = HTMLSanitizer.sanitize("<img src=\"x.png\" onerror=\"alert(1)\">")
        #expect(!result.contains("onerror"))
        #expect(result.contains("<img"))
    }

    @Test("<iframe> タグが除去されること")
    func sanitizerRemovesIframe() {
        let result = HTMLSanitizer.sanitize("<iframe src=\"evil.html\"></iframe>")
        #expect(!result.contains("<iframe"))
        #expect(!result.contains("evil.html"))
    }

    @Test("<object> タグが除去されること")
    func sanitizerRemovesObject() {
        let result = HTMLSanitizer.sanitize("<object data=\"payload\"></object>")
        #expect(!result.contains("<object"))
    }

    @Test("<form> タグが除去されること")
    func sanitizerRemovesForm() {
        let result = HTMLSanitizer.sanitize("<form action=\"/steal\"><input name=\"x\"></form>")
        #expect(!result.contains("<form"))
        #expect(!result.contains("/steal"))
    }

    @Test("style 属性が除去されること")
    func sanitizerRemovesStyleAttr() {
        let result = HTMLSanitizer.sanitize("<div style=\"background:url(javascript:)\">text</div>")
        #expect(!result.contains("style="))
        #expect(result.contains("text"))
    }

    @Test("大文字 <SCRIPT> も除去されること")
    func sanitizerRemovesScriptTagUppercase() {
        let result = HTMLSanitizer.sanitize("<SCRIPT>alert(1)</SCRIPT>")
        #expect(!result.lowercased().contains("<script"))
    }

    @Test("onclick 属性が除去されること")
    func sanitizerRemovesOnclick() {
        let result = HTMLSanitizer.sanitize("<a href=\"#\" onclick=\"alert(1)\">link</a>")
        #expect(!result.contains("onclick"))
        #expect(result.contains("<a"))
        #expect(result.contains("link"))
    }

    @Test("onmouseover 属性が除去されること")
    func sanitizerRemovesOnmouseover() {
        let result = HTMLSanitizer.sanitize("<span onmouseover=\"steal()\">hover</span>")
        #expect(!result.contains("onmouseover"))
        #expect(result.contains("hover"))
    }

    @Test("img の javascript: src が無害化されること")
    func sanitizerSanitizesJavascriptImgSrc() {
        let result = HTMLSanitizer.sanitize("<img src=\"javascript:alert(1)\">")
        #expect(!result.contains("javascript:"))
    }

    // MARK: - HTMLSanitizer: 正当系（保持確認）

    @Test("<details><summary> が保持されること")
    func sanitizerKeepsDetailsSummary() {
        let result = HTMLSanitizer.sanitize("<details><summary>見出し</summary><p>内容</p></details>")
        #expect(result.contains("<details>"))
        #expect(result.contains("<summary>"))
        #expect(result.contains("内容"))
    }

    @Test("HTML テーブルが保持されること")
    func sanitizerKeepsTable() {
        let html = "<table><thead><tr><th>Name</th></tr></thead><tbody><tr><td>Alice</td></tr></tbody></table>"
        let result = HTMLSanitizer.sanitize(html)
        #expect(result.contains("<table>"))
        #expect(result.contains("<th>"))
        #expect(result.contains("Alice"))
    }

    @Test("<br> が保持されること")
    func sanitizerKeepsBr() {
        let result = HTMLSanitizer.sanitize("line1<br>line2")
        #expect(result.contains("line1"))
        #expect(result.contains("line2"))
        // <br /> (self-closing) として保持される
        #expect(result.contains("br"))
    }

    @Test("<code><pre> が保持されること")
    func sanitizerKeepsCodePre() {
        let result = HTMLSanitizer.sanitize("<pre><code>let x = 1</code></pre>")
        #expect(result.contains("<pre>"))
        #expect(result.contains("<code>"))
        #expect(result.contains("let x = 1"))
    }

    @Test("class 属性が保持されること")
    func sanitizerKeepsClassAttr() {
        let result = HTMLSanitizer.sanitize("<span class=\"highlight\">text</span>")
        #expect(result.contains("class=\"highlight\""))
    }

    @Test("a href が保持されること")
    func sanitizerKeepsAHref() {
        let result = HTMLSanitizer.sanitize("<a href=\"https://example.com\">link</a>")
        #expect(result.contains("https://example.com"))
        #expect(result.contains("link"))
    }

    // MARK: - HTMLSanitizer: MarkdownService 統合（rawHTML パス）

    @Test("Markdown InlineHTML の <script> が除去されること")
    func markdownInlineHTMLScriptRemoved() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("Hello <script>alert(1)</script> world")
        #expect(!html.contains("<script"))
        #expect(!html.contains("alert(1)"))
    }

    @Test("Markdown HTMLBlock の <iframe> が除去されること")
    func markdownHTMLBlockIframeRemoved() {
        let svc = MarkdownService()
        let md = "before\n\n<iframe src=\"evil\"></iframe>\n\nafter"
        let html = svc.toBodyHTML(md)
        #expect(!html.contains("<iframe"))
        #expect(!html.contains("evil"))
    }

    @Test("Markdown の details/summary が保持されること")
    func markdownHTMLBlockDetailsSummaryKept() {
        let svc = MarkdownService()
        let md = "<details><summary>折りたたみ</summary><p>内容</p></details>"
        let html = svc.toBodyHTML(md)
        #expect(html.contains("<details>"))
        #expect(html.contains("折りたたみ"))
        #expect(html.contains("内容"))
    }

    @Test("Markdown の onerror 付き img が onerror なしで保持されること")
    func markdownInlineHTMLImgOnerrorRemoved() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("before <img src=\"ok.png\" onerror=\"alert(1)\"> after")
        #expect(!html.contains("onerror"))
        #expect(html.contains("<img"))
    }

    // MARK: - CSP nonce（KMD-242）

    @Test("CSP の script-src に 'unsafe-inline' が含まれないこと")
    func cspScriptSrcNoUnsafeInline() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")
        // CSP の meta content 文字列だけを取り出してチェック。
        // Mermaid.js バンドル内部に 'unsafe-inline' という文字列が含まれる可能性があるため
        // html 全体ではなく Content-Security-Policy content 属性値のみを対象にする。
        guard let cspStart = html.range(of: "Content-Security-Policy\" content=\""),
              let cspEnd = html.range(of: "\"", range: cspStart.upperBound..<html.endIndex)
        else {
            Issue.record("CSP meta タグが見つからない")
            return
        }
        let cspValue = String(html[cspStart.upperBound..<cspEnd.lowerBound])
        // script-src ディレクティブに 'unsafe-inline' が含まれないことを確認。
        // style-src 'unsafe-inline' は意図的に残す（CSS のインラインスタイル許可のため）。
        guard let scriptSrcRange = cspValue.range(of: "script-src ") else {
            Issue.record("CSP に script-src が見つからない: \(cspValue)")
            return
        }
        // script-src ディレクティブの値部分（次の ; まで）を抽出
        let afterScriptSrc = String(cspValue[scriptSrcRange.upperBound...])
        let scriptSrcValue = afterScriptSrc.components(separatedBy: ";").first ?? afterScriptSrc
        #expect(!scriptSrcValue.contains("'unsafe-inline'"),
                "script-src に 'unsafe-inline' が残っている: \(scriptSrcValue)")
    }

    @Test("CSP に nonce- が含まれること")
    func cspContainsNonce() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")
        #expect(html.contains("'nonce-"))
    }

    @Test("script タグに nonce 属性が付くこと")
    func scriptTagsHaveNonceAttr() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")
        // script タグが存在し nonce 属性を持つこと
        #expect(html.contains("<script nonce="))
    }

    @Test("CSP の nonce と script タグの nonce が一致すること")
    func cspNonceMatchesScriptNonce() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")

        // CSP から nonce 値を抽出: 'nonce-<value>'
        guard let cspRange = html.range(of: "Content-Security-Policy\" content=\""),
              let nonceStart = html.range(of: "'nonce-", range: cspRange.upperBound..<html.endIndex),
              let nonceEnd = html.range(of: "'", range: nonceStart.upperBound..<html.endIndex)
        else {
            Issue.record("CSP nonce が見つからない")
            return
        }
        let cspNonce = String(html[nonceStart.upperBound..<nonceEnd.lowerBound])
        #expect(!cspNonce.isEmpty)

        // script タグの nonce 属性値が CSP の nonce と一致すること
        let scriptNoncePattern = "nonce=\"\(cspNonce)\""
        #expect(html.contains(scriptNoncePattern), "script の nonce が CSP の nonce と不一致")
    }

    @Test("ロードごとに nonce が異なること")
    func nonceChangesPerLoad() {
        // nonce はロードごとに生成されるため、連続2回の呼び出しで異なる値になることを確認
        let n1 = MarkdownService.generateNonce()
        let n2 = MarkdownService.generateNonce()
        #expect(n1 != n2, "nonce が毎回同じ値になっている")
    }

    // MARK: - URL スキーム許可リスト（リンク）

    @Test("https リンクは許可されること")
    func linkHTTPS() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[title](https://example.com)")
        #expect(html.contains("href=\"https://example.com\""))
    }

    @Test("http リンクは許可されること")
    func linkHTTP() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[title](http://example.com)")
        #expect(html.contains("href=\"http://example.com\""))
    }

    @Test("mailto リンクは許可されること")
    func linkMailto() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[mail](mailto:user@example.com)")
        #expect(html.contains("href=\"mailto:user@example.com\""))
    }

    @Test("# アンカーリンクは許可されること")
    func linkAnchor() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[sec](#section)")
        #expect(html.contains("href=\"#section\""))
    }

    @Test("相対パスリンクは許可されること")
    func linkRelative() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[page](./doc.md)")
        #expect(html.contains("href=\"./doc.md\""))
    }

    @Test("javascript: リンクは無害化されること")
    func linkJavascriptRejected() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[xss](javascript:alert(1))")
        #expect(!html.contains("javascript:"))
        #expect(html.contains("href=\"#\""))
    }

    @Test("大文字 JaVaScRiPt: リンクも無害化されること")
    func linkJavascriptCaseInsensitive() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[xss](JaVaScRiPt:alert(1))")
        #expect(!html.lowercased().contains("javascript:"))
        #expect(html.contains("href=\"#\""))
    }

    @Test("先頭空白 ` javascript:` リンクも無害化されること")
    func linkJavascriptWithLeadingSpace() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[xss]( javascript:alert(1))")
        #expect(!html.lowercased().contains("javascript:"))
        #expect(html.contains("href=\"#\""))
    }

    @Test("data:text/html リンクは無害化されること")
    func linkDataTextHtmlRejected() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[xss](data:text/html,<script>alert(1)</script>)")
        #expect(!html.contains("data:text/html"))
        #expect(html.contains("href=\"#\""))
    }

    @Test("percent-encoding された javascript: リンクも無害化されること")
    func linkPercentEncodedJavascriptRejected() {
        // %6a%61%76%61%73%63%72%69%70%74%3a = javascript:
        let svc = MarkdownService()
        let html = svc.toBodyHTML("[xss](%6a%61%76%61%73%63%72%69%70%74%3aalert(1))")
        #expect(!html.lowercased().contains("javascript:"))
        #expect(html.contains("href=\"#\""))
    }

    // MARK: - URL スキーム許可リスト（画像）

    @Test("https 画像は許可されること")
    func imageHTTPS() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("![alt](https://example.com/img.png)")
        #expect(html.contains("src=\"https://example.com/img.png\""))
    }

    @Test("data:image 画像は許可されること")
    func imageDataImage() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("![alt](data:image/png;base64,abc==)")
        #expect(html.contains("src=\"data:image/png;base64,abc==\""))
    }

    @Test("javascript: 画像 src は無害化されること")
    func imageJavascriptRejected() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("![alt](javascript:alert(1))")
        #expect(!html.contains("javascript:"))
        #expect(html.contains("src=\"\""))
    }

    @Test("data:text/html 画像 src は無害化されること")
    func imageDataTextHtmlRejected() {
        let svc = MarkdownService()
        let html = svc.toBodyHTML("![alt](data:text/html,xss)")
        #expect(!html.contains("data:text/html"))
        #expect(html.contains("src=\"\""))
    }

    // MARK: - CSP メタタグ

    @Test("生成 HTML に CSP メタタグが含まれること")
    func cspMetaTagPresent() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src"))
    }

    @Test("CSP に script-src が含まれること")
    func cspContainsScriptSrc() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")
        #expect(html.contains("script-src"))
    }

    @Test("CSP に connect-src 'none' が含まれること")
    func cspConnectSrcNone() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")
        #expect(html.contains("connect-src") && html.contains("'none'"))
    }

    // MARK: - Mermaid securityLevel

    @Test("mermaid.initialize が securityLevel: 'strict' を使うこと")
    func mermaidSecurityLevelStrict() {
        let svc = MarkdownService()
        let html = svc.toHTML("hello")
        #expect(html.contains("securityLevel: 'strict'"))
        #expect(!html.contains("securityLevel: 'loose'"))
    }

    // MARK: - WorkspacePreviewHTTPServer: symlink 越え拒否ロジック検証

    @Test("symlink 解決後に serve root 外を指すパスは prefix チェックで弾かれること")
    func symlinkResolvingRejectsOutsidePath() throws {
        let rootWS = try TempWorkspace()
        let outsideWS = try TempWorkspace()
        let root = rootWS.root
        let outside = outsideWS.root

        let secret = try outsideWS.write("secret content", to: "secret.txt")
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        // WorkspacePreviewHTTPServer が採用している symlink 解決 + prefix チェックのロジックを直接検証
        let resolvedLink = link.resolvingSymlinksInPath()
        let resolvedRoot = root.resolvingSymlinksInPath()
        // symlink は root 外を指すため prefix チェックが失敗（= 403 相当）になることを確認
        let isAllowed = resolvedLink.path.hasPrefix(resolvedRoot.path + "/")
            || resolvedLink.path == resolvedRoot.path
        #expect(!isAllowed, "symlink 越えは弾かれるべき")
    }

    // MARK: - KMD-242 followup: nonce フォールバック・タブ区切りタグ

    @Test("generateNonce は空文字列を返さないこと")
    func nonceIsNeverEmpty() {
        // SecRandomCopyBytes 失敗経路を直接テストはできないが、
        // 通常経路で空文字列が返らないことを確認する
        let nonce = MarkdownService.generateNonce()
        #expect(!nonce.isEmpty, "nonce は空であってはならない")
    }

    @Test("generateNonce の結果は有効な Base64 文字列であること")
    func nonceIsValidBase64() {
        let nonce = MarkdownService.generateNonce()
        // Base64 文字セット: A-Z, a-z, 0-9, +, /, = のみ
        let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        #expect(nonce.unicodeScalars.allSatisfy { base64Chars.contains($0) },
                "nonce に Base64 以外の文字が含まれている: \(nonce)")
    }

    @Test("タブ区切りの許可タグ属性がサニタイズ後も保持されること")
    func tabSeparatedAttributeIsPreserved() {
        // <img\tsrc="a.png"> のようにタブで区切られた属性は正当な HTML
        // firstIndex(of: " ") だと検出されず除去される誤陰性を防ぐ
        let html = HTMLSanitizer.sanitize("<img\tsrc=\"a.png\">")
        #expect(html.contains("<img"), "タブ区切り属性のある img タグが除去されてはならない")
    }

    @Test("タブ区切りの非許可タグは除去されること")
    func tabSeparatedNonAllowedTagIsRemoved() {
        let html = HTMLSanitizer.sanitize("<script\ttype=\"text/javascript\">alert(1)</script>")
        #expect(!html.contains("<script"), "タブ区切りでも script タグは除去されるべき")
        #expect(!html.contains("alert(1)"), "script の内容テキストも除去されるべき")
    }

    @Test("serve root 内の正規ファイルは prefix チェックを通過すること")
    func normalFilePassesPrefixCheck() throws {
        let ws = try TempWorkspace()
        let file = try ws.write("content", to: "readme.md")

        let resolvedFile = file.resolvingSymlinksInPath()
        let resolvedRoot = ws.root.resolvingSymlinksInPath()
        let isAllowed = resolvedFile.path.hasPrefix(resolvedRoot.path + "/")
            || resolvedFile.path == resolvedRoot.path
        #expect(isAllowed, "root 内の通常ファイルは通過するべき")
    }
}
