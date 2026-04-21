import SwiftUI
import WebKit

struct D2WebView: NSViewRepresentable {
    let svg: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsMagnification = true
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
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { box-sizing: border-box; }
        html, body {
            margin: 0;
            padding: 0;
            background: #fdfcf8;
            overflow: hidden;
            width: 100vw;
            height: 100vh;
        }
        svg {
            display: block;
            width: 100%;
            height: 100%;
        }
        </style>
        <script>\(BundledJS.svgPanZoom)</script>
        </head>
        <body>
        \(svg)
        <script>
        window.addEventListener('load', function () {
            const svg = document.querySelector('svg');
            if (!svg) { return; }

            if (!svg.hasAttribute('viewBox')) {
                const widthAttr = svg.getAttribute('width');
                const heightAttr = svg.getAttribute('height');
                const width = widthAttr ? parseFloat(widthAttr) : NaN;
                const height = heightAttr ? parseFloat(heightAttr) : NaN;

                if (!Number.isNaN(width) && !Number.isNaN(height) && width > 0 && height > 0) {
                    svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
                }
            }

            svg.removeAttribute('width');
            svg.removeAttribute('height');

            svgPanZoom(svg, {
                zoomEnabled: true,
                controlIconsEnabled: true,
                fit: true,
                center: true,
                minZoom: 0.05,
                maxZoom: 20,
                mouseWheelZoomEnabled: true
            });
        });
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator {
        var lastSVG: String?
    }
}
