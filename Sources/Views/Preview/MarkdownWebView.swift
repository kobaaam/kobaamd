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

        if (!coord.isLoaded || coord.lastShellHTML != shellHTML) && !shellHTML.isEmpty {
            // 初回 or CSS/シェル変更時：フル HTML をリロード
            coord.isLoaded = true
            coord.lastShellHTML = shellHTML
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
        var lastShellHTML: String = ""
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
                      let line = note.userInfo?["sourceLine"] as? Int,
                      let wv = self.webView else { return }
                self.highlightBySourceLine(line, in: wv)
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

        private func highlightBySourceLine(_ cursorLine: Int, in wv: WKWebView) {
            let js = """
            (function(cursorLine) {
              // 前のハイライトを消す（tr の場合は td/th 子要素も）
              document.querySelectorAll('[data-koba-active]').forEach(function(el) {
                el.removeAttribute('data-koba-active');
                el.style.removeProperty('background-color');
                el.style.removeProperty('border-radius');
                el.querySelectorAll('td, th').forEach(function(c) {
                  c.style.removeProperty('background-color');
                });
              });
              var blocks = document.querySelectorAll('[data-source-line-start]');
              var best = null;
              var bestStart = -1;
              // start <= cursorLine <= end の中で最も内側（start が最大）を選ぶ
              for (var i = 0; i < blocks.length; i++) {
                var start = parseInt(blocks[i].dataset.sourceLineStart, 10);
                var end   = parseInt(blocks[i].dataset.sourceLineEnd,   10);
                if (start <= cursorLine && cursorLine <= end && start >= bestStart) {
                  best = blocks[i];
                  bestStart = start;
                }
              }
              // フォールバック: cursorLine より前の最後のブロック
              if (!best) {
                for (var i = 0; i < blocks.length; i++) {
                  var start = parseInt(blocks[i].dataset.sourceLineStart, 10);
                  if (start <= cursorLine) { best = blocks[i]; }
                  else { break; }
                }
              }
              if (best) {
                best.setAttribute('data-koba-active', '');
                best.style.borderRadius = '4px';
                // tr の場合は td/th に直接色を付ける（CSS specificity 対策）
                if (best.tagName === 'TR') {
                  best.querySelectorAll('td, th').forEach(function(c) {
                    c.style.backgroundColor = 'rgba(255,91,31,0.08)';
                  });
                } else {
                  best.style.backgroundColor = 'rgba(255,91,31,0.08)';
                }
                // カーソル行のブロックをプレビューに追従させる
                // ビューポート外なら中央にスクロール、内なら動かさない
                var rect = best.getBoundingClientRect();
                if (rect.top < 0 || rect.bottom > window.innerHeight) {
                  best.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
              }
            })(\(cursorLine));
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
