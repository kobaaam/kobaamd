import SwiftUI
import WebKit

struct D2WebView: NSViewRepresentable {
    let svg: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        loadSVGIfNeeded(into: webView, context: context)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        loadSVGIfNeeded(into: nsView, context: context)
    }

    private func loadSVGIfNeeded(into webView: WKWebView, context: Context) {
        guard context.coordinator.lastSVG != svg else { return }
        context.coordinator.lastSVG = svg
        webView.loadHTMLString(
            htmlShell(for: svg),
            baseURL: URL(string: "https://kobaamd-preview.local/")
        )
    }

    private func htmlShell(for svg: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        html, body { background: #fdfcf8; width: 100%; height: 100%; }
        body { display: flex; justify-content: center; align-items: flex-start; padding: 24px; }
        svg { max-width: 100%; height: auto; }
        </style></head><body>\(svg)</body></html>
        """
    }

    final class Coordinator {
        var lastSVG: String?
    }
}
