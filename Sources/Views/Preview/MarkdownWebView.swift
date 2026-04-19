import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let scrollRatio: Double

    init(html: String, scrollRatio: Double = 0) {
        self.html = html
        self.scrollRatio = scrollRatio
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let scriptSource = """
        document.documentElement.style.webkitUserSelect='none';
        document.documentElement.style.webkitTouchCallout='none';
        """
        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            // Use a base URL so the WKWebView treats this as a real origin,
            // which allows loading CDN resources (Mermaid.js, etc.)
            webView.loadHTMLString(html, baseURL: URL(string: "https://kobaamd-preview.local/"))
            context.coordinator.lastHTML = html
            // スクロール同期はページ読み込み後に適用するためnavigationDelegateで処理
            context.coordinator.pendingScrollRatio = scrollRatio
            webView.navigationDelegate = context.coordinator
        } else {
            syncScroll(webView: webView, ratio: scrollRatio)
        }
    }

    private func syncScroll(webView: WKWebView, ratio: Double) {
        let js = "window.scrollTo(0, \(ratio) * Math.max(document.body.scrollHeight - window.innerHeight, 0));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        var pendingScrollRatio: Double = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = "window.scrollTo(0, \(pendingScrollRatio) * Math.max(document.body.scrollHeight - window.innerHeight, 0));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
