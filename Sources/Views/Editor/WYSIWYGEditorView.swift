import SwiftUI
import WebKit

// MARK: - WYSIWYG Markdown editor (EasyMDE via CDN)
//
// Word-like editing experience: renders Markdown formatting inline.
// Bidirectional sync:
//   Swift → JS: evaluateJavaScript("_setContent(...)")
//   JS → Swift: WKScriptMessageHandler "textChanged"
//
// Initial content is pushed via _setContent after page load (avoids JS injection issues).

struct WYSIWYGEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pendingText = text

        webView.loadHTMLString(Self.htmlTemplate,
                               baseURL: URL(string: "https://kobaamd-wysiwyg.local/"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Push text to JS only when changed externally (not from JS)
        if context.coordinator.lastTextFromJS != text {
            context.coordinator.pendingText = text
            context.coordinator.pushTextIfReady()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WYSIWYGEditorView
        weak var webView: WKWebView?
        var isReady = false
        var pendingText: String?
        var lastTextFromJS: String = ""

        init(_ parent: WYSIWYGEditorView) {
            self.parent = parent
        }

        // JS → Swift
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "textChanged",
                  let newText = message.body as? String else { return }
            lastTextFromJS = newText
            DispatchQueue.main.async { self.parent.text = newText }
        }

        // Page loaded → push pending initial text
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            pushTextIfReady()
        }

        func pushTextIfReady() {
            guard isReady, let text = pendingText, let webView else { return }
            pendingText = nil
            // Pass via JSON to handle all special characters safely
            guard let jsonData = try? JSONEncoder().encode(text),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
            webView.evaluateJavaScript("_setContent(\(jsonStr))", completionHandler: nil)
        }
    }

    // MARK: - Static HTML template (no initial value injection — pushed after load)

    // Inlines bundled JS/CSS for offline support. Falls back to CDN if resources are missing.
    static let htmlTemplate: String = _makeEasyMDETemplate()
}

// MARK: - HTML template builder (free function avoids Swift parser issues with static let closures)

private func _makeEasyMDETemplate() -> String {
    let css = BundledJS.easymdeCss.isEmpty
        ? #"<link rel="stylesheet" href="https://unpkg.com/easymde/dist/easymde.min.css">"#
        : "<style>" + BundledJS.easymdeCss + "</style>"
    let js = BundledJS.easymdeJS.isEmpty
        ? #"<script src="https://unpkg.com/easymde/dist/easymde.min.js"></script>"#
        : "<script>" + BundledJS.easymdeJS + "</script>"

    let head = """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
    <meta charset="utf-8">
    """
    let styles = """
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      html, body { height: 100%; background: #fdfcf8; }
      .EasyMDEContainer { height: 100%; display: flex; flex-direction: column; }
      .EasyMDEContainer .CodeMirror {
        flex: 1; height: auto;
        font-family: "SF Mono", Menlo, monospace;
        font-size: 14px; line-height: 1.6;
        background: #fdfcf8; color: #1a1a1a;
        border: none;
      }
      .editor-toolbar {
        background: #ffffff;
        border-bottom: 1px solid #e0ddd8;
        border-top: none; border-left: none; border-right: none;
        opacity: 1;
      }
      .editor-toolbar a { color: #555 !important; }
      .editor-toolbar a:hover, .editor-toolbar a.active { background: #f0efec; }
      .CodeMirror-scroll { padding: 12px 16px; }
      .editor-preview {
        background: #fdfcf8; color: #1a1a1a;
        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        font-size: 15px; line-height: 1.7; padding: 20px 32px;
      }
      .editor-preview h1, .editor-preview h2, .editor-preview h3 { margin: 1em 0 0.4em; }
      .editor-preview p { margin: 0.6em 0; }
      .editor-preview code { background: #f0efec; border-radius: 3px; padding: 1px 4px; }
      .editor-preview pre { background: #f0efec; padding: 12px; border-radius: 6px; }
      .editor-preview blockquote { border-left: 3px solid #FF5B1F; padding-left: 12px; color: #555; }
      .editor-statusbar { display: none; }
    </style>
    </head>
    <body>
    <textarea id="editor"></textarea>
    """
    let script = """
    <script>
      var easyMDE = new EasyMDE({
        element: document.getElementById('editor'),
        autofocus: true,
        spellChecker: false,
        toolbar: [
          'bold','italic','strikethrough','|',
          'heading-1','heading-2','heading-3','|',
          'unordered-list','ordered-list','|',
          'link','image','code','|',
          'preview','side-by-side','|','guide'
        ],
        renderingConfig: { singleLineBreaks: false },
        status: false,
      });

      var _ignoreNext = false;
      easyMDE.codemirror.on('change', function() {
        if (_ignoreNext) { _ignoreNext = false; return; }
        window.webkit.messageHandlers.textChanged.postMessage(easyMDE.value());
      });

      function _setContent(text) {
        _ignoreNext = true;
        easyMDE.value(text);
      }
    </script>
    </body>
    </html>
    """

    return head + "\n" + css + "\n" + styles + "\n" + js + "\n" + script
}
