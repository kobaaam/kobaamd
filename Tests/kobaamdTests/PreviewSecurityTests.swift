import Foundation
import Testing
@testable import kobaamd

@Suite("Preview security hardening")
struct PreviewSecurityTests {

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
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let secret = outside.appendingPathComponent("secret.txt")
        try "secret content".write(to: secret, atomically: true, encoding: .utf8)

        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        // WorkspacePreviewHTTPServer が採用している symlink 解決 + prefix チェックのロジックを直接検証
        let resolvedLink = link.resolvingSymlinksInPath()
        let resolvedRoot = root.resolvingSymlinksInPath()
        // symlink は root 外を指すため prefix チェックが失敗（= 403 相当）になることを確認
        let isAllowed = resolvedLink.path.hasPrefix(resolvedRoot.path + "/")
            || resolvedLink.path == resolvedRoot.path
        #expect(!isAllowed, "symlink 越えは弾かれるべき")

        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    @Test("serve root 内の正規ファイルは prefix チェックを通過すること")
    func normalFilePassesPrefixCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent("readme.md")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let resolvedFile = file.resolvingSymlinksInPath()
        let resolvedRoot = root.resolvingSymlinksInPath()
        let isAllowed = resolvedFile.path.hasPrefix(resolvedRoot.path + "/")
            || resolvedFile.path == resolvedRoot.path
        #expect(isAllowed, "root 内の通常ファイルは通過するべき")

        try? FileManager.default.removeItem(at: root)
    }
}
