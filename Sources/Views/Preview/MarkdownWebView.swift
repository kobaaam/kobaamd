import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    let html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
