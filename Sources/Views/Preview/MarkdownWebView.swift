import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    /// フル HTML（初回ロード用シェル）
    let shellHTML: String
    /// ボディコンテンツのみ（差分更新用）
    let bodyHTML: String
    let scrollRatio: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator

        if !coord.isLoaded && !shellHTML.isEmpty {
            // 初回：フル HTML をロードしてシェル（CSS・mermaid.js）を確立
            coord.isLoaded = true
            coord.lastBodyHTML = bodyHTML
            coord.pendingScrollRatio = scrollRatio
            PerfLogger.begin("WebViewLoad")
            webView.loadHTMLString(shellHTML, baseURL: URL(string: "https://kobaamd-preview.local/"))
        } else if coord.lastBodyHTML != bodyHTML {
            // 差分更新：ページナビゲーションなしでボディだけ差し替え
            coord.lastBodyHTML = bodyHTML
            coord.pendingScrollRatio = scrollRatio
            injectBody(bodyHTML, into: webView, scrollRatio: scrollRatio)
        } else {
            syncScroll(webView: webView, ratio: scrollRatio)
        }
    }

    // MARK: - Helpers

    private func injectBody(_ body: String, into webView: WKWebView, scrollRatio: Double) {
        // body を JS 文字列として安全にエスケープ
        let escaped = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let js = """
        (function() {
          var oldScrollY = window.scrollY;
          var oldHeight = document.body.scrollHeight;
          document.body.innerHTML = `\(escaped)`;
          // mermaid ダイアグラムを再変換・再描画
          document.querySelectorAll('pre > code.language-mermaid').forEach(function(el) {
            var div = document.createElement('div');
            div.className = 'mermaid';
            div.textContent = el.textContent;
            el.parentNode.replaceWith(div);
          });
          if (typeof mermaid !== 'undefined') {
            mermaid.run({ querySelector: '.mermaid' });
          }
          if (oldHeight > 0) {
            window.scrollTo(0, oldScrollY * document.body.scrollHeight / oldHeight);
          }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func syncScroll(webView: WKWebView, ratio: Double) {
        let js = "window.scrollTo(0, \(ratio) * Math.max(document.body.scrollHeight - window.innerHeight, 0));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded = false
        var lastBodyHTML: String = ""
        var pendingScrollRatio: Double = 0
        weak var webView: WKWebView?
        private var blockObserver: Any?

        override init() {
            super.init()
            blockObserver = NotificationCenter.default.addObserver(
                forName: .cursorBlockChanged,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self,
                      let idx = note.userInfo?["blockIndex"] as? Int,
                      let wv = self.webView else { return }
                self.highlightBlock(idx, in: wv)
            }
        }

        deinit {
            if let blockObserver { NotificationCenter.default.removeObserver(blockObserver) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            PerfLogger.end("WebViewLoad")
            let js = "window.scrollTo(0, \(pendingScrollRatio) * Math.max(document.body.scrollHeight - window.innerHeight, 0));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func highlightBlock(_ idx: Int, in wv: WKWebView) {
            let js = """
            (function(idx) {
              document.querySelectorAll('[data-koba-active]').forEach(function(el) {
                el.removeAttribute('data-koba-active');
                el.style.removeProperty('background-color');
                el.style.removeProperty('border-radius');
              });
              var blocks = document.querySelectorAll(
                'body > p, body > h1, body > h2, body > h3, body > h4, body > h5, body > h6, body > ul, body > ol, body > pre, body > blockquote, body > table'
              );
              if (idx >= 0 && idx < blocks.length) {
                var el = blocks[idx];
                el.setAttribute('data-koba-active', '');
                el.style.backgroundColor = 'rgba(255,91,31,0.08)';
                el.style.borderRadius = '4px';
              }
            })(\(idx));
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
