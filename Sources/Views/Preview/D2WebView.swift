import Foundation
import SwiftUI
import WebKit

struct D2WebView: NSViewRepresentable {
    let svg: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsMagnification = false
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

    func sanitizeSVG(_ svg: String) -> String {
        let patterns = [
            #"<script\b[^>]*>[\s\S]*?</script\s*>"#,
            #"<script\b[^>]*/\s*>"#
        ]
        let eventHandlerPatterns = [
            "\\son\\w+\\s*=\\s*\"[^\"]*\"",
            "\\son\\w+\\s*=\\s*'[^']*'"
        ]

        var sanitized = svg
        for pattern in patterns {
            sanitized = sanitized.replacingMatches(
                of: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        }
        for pattern in eventHandlerPatterns {
            sanitized = sanitized.replacingMatches(of: pattern, options: [.caseInsensitive])
        }
        return sanitized
    }

    private func htmlShell(for svg: String) -> String {
        let sanitizedSVG = sanitizeSVG(svg)
        return """
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
        \(sanitizedSVG)
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

            const panZoom = svgPanZoom(svg, {
                zoomEnabled: true,
                controlIconsEnabled: true,
                fit: true,
                center: true,
                minZoom: 0.05,
                maxZoom: 20,
                mouseWheelZoomEnabled: true
            });

            let lastScale = 1;
            document.addEventListener('gesturestart', function(e) {
                e.preventDefault();
                lastScale = 1;
            });
            document.addEventListener('gesturechange', function(e) {
                e.preventDefault();
                const relativeScale = e.scale / lastScale;
                lastScale = e.scale;
                panZoom.zoomAtPointBy(relativeScale, { x: e.clientX, y: e.clientY });
            });
            document.addEventListener('gestureend', function(e) {
                e.preventDefault();
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

private extension String {
    func replacingMatches(
        of pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return self
        }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }
}
