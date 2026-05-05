import Foundation
import SwiftUI
import WebKit

struct D2WebView: NSViewRepresentable {
    let d2Code: String
    let viewModel: D2PreviewViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, sanitizer: sanitizeSVG)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "d2Bridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = false

        context.coordinator.webView = webView
        loadShellIfNeeded(into: webView, coordinator: context.coordinator)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.viewModel = viewModel
        coordinator.webView = webView

        loadShellIfNeeded(into: webView, coordinator: coordinator)

        guard coordinator.lastCode != d2Code else { return }
        coordinator.lastCode = d2Code

        if coordinator.isReady {
            coordinator.render(code: d2Code)
        } else {
            coordinator.pendingCode = d2Code
        }
    }

    private func loadShellIfNeeded(into webView: WKWebView, coordinator: Coordinator) {
        guard !coordinator.isLoaded else { return }

        coordinator.isLoaded = true
        coordinator.isReady = false
        webView.loadHTMLString(
            htmlShell(),
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

    private func htmlShell() -> String {
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
        #canvas {
            width: 100%;
            height: 100%;
        }
        svg {
            display: block;
            width: 100%;
            height: 100%;
        }
        </style>
        <script>\(escapedForInlineScript(BundledJS.svgPanZoom))</script>
        <script type="module">
        \(escapedForInlineScript(wrappedD2Module()))
        </script>
        <script>
        let d2Instance = null;

        async function ensureD2() {
            if (d2Instance) { return d2Instance; }
            if (typeof D2 === 'undefined') {
                throw new Error('D2 module not available');
            }
            d2Instance = new D2();
            return d2Instance;
        }

        function attachGestureHandlers(panZoom) {
            if (window.__d2GestureHandlersAttached) { return; }
            window.__d2GestureHandlersAttached = true;

            let lastScale = 1;
            document.addEventListener('gesturestart', function (e) {
                e.preventDefault();
                lastScale = 1;
            });
            document.addEventListener('gesturechange', function (e) {
                e.preventDefault();
                const relativeScale = e.scale / lastScale;
                lastScale = e.scale;
                if (window.__d2PanZoom) {
                    window.__d2PanZoom.zoomAtPointBy(relativeScale, { x: e.clientX, y: e.clientY });
                }
            });
            document.addEventListener('gestureend', function (e) {
                e.preventDefault();
            });
        }

        async function renderD2(code) {
            try {
                const canvas = document.getElementById('canvas');
                if (window.__d2PanZoom && typeof window.__d2PanZoom.destroy === 'function') {
                    window.__d2PanZoom.destroy();
                    window.__d2PanZoom = null;
                }

                if (!code || !code.trim()) {
                    canvas.innerHTML = '';
                    return;
                }

                const d2 = await ensureD2();
                const result = await d2.compile(code);
                const svg = await d2.render(result.diagram, result.renderOptions);

                canvas.innerHTML = svg;

                const svgEl = canvas.querySelector('svg');
                if (svgEl) {
                    if (!svgEl.hasAttribute('viewBox')) {
                        const width = parseFloat(svgEl.getAttribute('width') || 'NaN');
                        const height = parseFloat(svgEl.getAttribute('height') || 'NaN');
                        if (!Number.isNaN(width) && !Number.isNaN(height) && width > 0 && height > 0) {
                            svgEl.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
                        }
                    }

                    svgEl.removeAttribute('width');
                    svgEl.removeAttribute('height');

                    const panZoom = svgPanZoom(svgEl, {
                        zoomEnabled: true,
                        controlIconsEnabled: true,
                        fit: true,
                        center: true,
                        minZoom: 0.05,
                        maxZoom: 20,
                        mouseWheelZoomEnabled: true
                    });
                    window.__d2PanZoom = panZoom;
                    attachGestureHandlers(panZoom);
                }

                window.webkit.messageHandlers.d2Bridge.postMessage(JSON.stringify({
                    type: 'svg',
                    payload: svg
                }));
            } catch (err) {
                window.webkit.messageHandlers.d2Bridge.postMessage(JSON.stringify({
                    type: 'error',
                    payload: (err && err.message) ? err.message : String(err)
                }));
            }
        }

        window.addEventListener('load', function () {
            ensureD2()
                .then(function () {
                    window.webkit.messageHandlers.d2Bridge.postMessage(JSON.stringify({
                        type: 'ready',
                        payload: ''
                    }));
                })
                .catch(function (err) {
                    window.webkit.messageHandlers.d2Bridge.postMessage(JSON.stringify({
                        type: 'error',
                        payload: 'WASM load failed: ' + ((err && err.message) ? err.message : String(err))
                    }));
                });
        });
        </script>
        </head>
        <body>
        <div id="canvas"></div>
        </body>
        </html>
        """
    }

    private func wrappedD2Module() -> String {
        var js = BundledJS.d2BrowserJS
        js = js.replacingMatches(
            of: #"export\s*\{\s*([A-Za-z_$][\w$]*)\s+as\s+D2\s*\}\s*;?\s*$"#,
            options: [],
            with: "globalThis.D2 = $1;"
        )
        js = js.replacingMatches(
            of: #"export\s*\{\s*D2\s*\}\s*;?\s*$"#,
            options: [],
            with: "globalThis.D2 = D2;"
        )
        return js
    }

    private func escapedForInlineScript(_ source: String) -> String {
        source.replacingOccurrences(of: "</script>", with: #"<\/script>"#)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var viewModel: D2PreviewViewModel
        let sanitizer: (String) -> String
        weak var webView: WKWebView?
        var isLoaded = false
        var isReady = false
        var lastCode: String?
        var pendingCode: String?

        init(viewModel: D2PreviewViewModel, sanitizer: @escaping (String) -> String) {
            self.viewModel = viewModel
            self.sanitizer = sanitizer
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "d2Bridge" else { return }

            let body: String
            if let text = message.body as? String {
                body = text
            } else {
                body = String(describing: message.body)
            }

            guard let data = body.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(BridgeMessage.self, from: data) else {
                Task { @MainActor [viewModel] in
                    viewModel.svg = ""
                    viewModel.errorMessage = "D2 bridge returned an invalid message."
                    viewModel.isRendering = false
                }
                return
            }

            switch payload.type {
            case "svg":
                let sanitized = sanitizer(payload.payload)
                Task { @MainActor [viewModel] in
                    viewModel.svg = sanitized
                    viewModel.errorMessage = nil
                    viewModel.isRendering = false
                }
            case "error":
                Task { @MainActor [viewModel] in
                    viewModel.svg = ""
                    viewModel.errorMessage = payload.payload
                    viewModel.isRendering = false
                }
            case "ready":
                isReady = true
                if let pendingCode {
                    self.pendingCode = nil
                    render(code: pendingCode)
                }
            default:
                break
            }
        }

        func render(code: String) {
            guard let webView else {
                pendingCode = code
                return
            }

            pendingCode = code
            webView.callAsyncJavaScript(
                """
                await renderD2(code);
                return null;
                """,
                arguments: ["code": code],
                in: nil,
                in: .page
            ) { [weak self] (result: Result<Any, Error>) in
                guard case .failure(let error) = result else { return }
                Task { @MainActor [viewModel = self?.viewModel] in
                    guard let viewModel else { return }
                    viewModel.svg = ""
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.isRendering = false
                }
            }
        }

        private struct BridgeMessage: Decodable {
            let type: String
            let payload: String
        }
    }
}

private extension String {
    func replacingMatches(
        of pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        replacingMatches(of: pattern, options: options, with: "")
    }

    func replacingMatches(
        of pattern: String,
        options: NSRegularExpression.Options = [],
        with template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return self
        }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }
}
