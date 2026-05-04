import Testing
@testable import kobaamd

@Suite("ConfluenceService XSS")
struct ConfluenceServiceXSSTests {
    let svc = ConfluenceService()

    @Test("javascript リンクが出力されないこと")
    func blocksJavascriptLink() {
        let html = svc.convertToStorageFormat("[label](javascript:alert(1))")

        #expect(!html.localizedCaseInsensitiveContains("javascript:"))
        #expect(html.contains("<a>label</a>"))
    }

    @Test("通常リンクの属性値で & がエスケープされること")
    func escapesAmpersandInHref() {
        let html = svc.convertToStorageFormat("[label](https://example.com?a=1&b=2)")

        #expect(html.contains(#"<a href="https://example.com?a=1&amp;b=2">label</a>"#))
    }

    @Test("href 属性内のダブルクォートがエスケープされること")
    func escapesQuotesInHref() {
        let markdown = #"[label](<https://example.com?x="onmouseover="alert(1)>)"#
        let html = svc.convertToStorageFormat(markdown)

        #expect(html.contains("&quot;onmouseover=&quot;alert(1)"))
        #expect(!html.contains(#""onmouseover=""#))
    }

    @Test("javascript 画像 URL が出力されないこと")
    func blocksJavascriptImage() {
        let html = svc.convertToStorageFormat("![alt](javascript:alert(1))")

        #expect(!html.localizedCaseInsensitiveContains("javascript:"))
        #expect(html.contains("<ac:image></ac:image>"))
    }

    @Test("data: スキーム画像はそのまま通過すること（MR-4 スコープ外）")
    func passesDataSchemeImage() {
        let dataURI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let html = svc.convertToStorageFormat("![alt](\(dataURI))")

        #expect(html.contains("<ac:image><ri:url ri:value=\""))
        #expect(html.contains("data:image/png;base64,"))
        #expect(!html.contains("<ac:image></ac:image>"))
    }

    @Test("vbscript: スキームはブロックせずそのまま通過すること（MR-4 スコープ外）")
    func passesVbscriptScheme() {
        let html = svc.convertToStorageFormat("[label](vbscript:msgbox(1))")

        #expect(html.contains(#"<a href="vbscript:msgbox(1)">label</a>"#))
    }

    @Test("画像属性内のダブルクォートがエスケープされること")
    func escapesQuotesInImageURL() {
        let markdown = #"![alt](<"onerror="alert(1)>)"#
        let html = svc.convertToStorageFormat(markdown)

        #expect(html.contains("&quot;onerror=&quot;alert(1)"))
        #expect(!html.contains(#""onerror=""#))
    }

    @Test("通常リンクの出力は維持されること")
    func keepsNormalLinkOutput() {
        let html = svc.convertToStorageFormat("[label](https://example.com)")

        #expect(html.contains(#"<a href="https://example.com">label</a>"#))
    }
}
