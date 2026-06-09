import SwiftUI
import WebKit

/// `interval` 間隔の **throttle**（leading + trailing edge）。
///
/// 連続スクロール中も `interval` ごとに flush するため preview 側がスムーズに追従する。
/// 名前を `Debouncer` から `Throttle` に変更したのは、debounce（最後の入力から N ms 静止
/// するまで遅延）ではなく throttle（N ms ごとに最新値を出力）が実装の正しい意味だから。
/// init 引数名 `delay` は呼び出し側互換のため残してある。
@MainActor
final class ScrollSyncThrottle {
    private let interval: Duration
    private let onFlush: @MainActor (Double, String) -> Void
    private var pendingRatio: Double?
    private var pendingSource: String = "unknown"
    private var trailingTask: Task<Void, Never>?
    private var lastFlushed: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    init(delay: Duration = .milliseconds(16), onFlush: @escaping @MainActor (Double, String) -> Void) {
        self.interval = delay
        self.onFlush = onFlush
    }

    deinit {
        trailingTask?.cancel()
    }

    func schedule(ratio: Double, source: String) {
        pendingRatio = ratio
        pendingSource = source

        let now = clock.now
        if let last = lastFlushed, now - last < interval {
            // interval 未満なら trailing flush だけ予約（既にあれば再利用）
            if trailingTask == nil {
                let interval = interval
                trailingTask = Task { [weak self] in
                    try? await Task.sleep(for: interval)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        // sleep 後と MainActor スイッチ後の double-check で
                        // schedule(...) 中の cancel と interleave しても誤発火しないように。
                        guard let self else { return }
                        if Task.isCancelled { return }
                        self.flushPending()
                    }
                }
            }
            return
        }

        // leading-edge 即時 flush
        flushPending()
    }

    private func flushPending() {
        trailingTask?.cancel()
        trailingTask = nil
        guard let ratio = pendingRatio else { return }
        let source = pendingSource
        pendingRatio = nil
        lastFlushed = clock.now
        onFlush(ratio, source)
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let appViewModel: AppViewModel
    /// フル HTML（初回ロード用シェル）
    let shellHTML: String
    /// 巨大な shellHTML の差し替え通知用バージョン
    let shellVersion: Int
    /// ボディコンテンツのみ（差分更新用）
    let bodyHTML: String

    func makeCoordinator() -> Coordinator {
        Coordinator(appViewModel: appViewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        PerfLogger.begin("MarkdownWebView.makeNSView")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "previewLineSelected")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        PerfLogger.end("MarkdownWebView.makeNSView")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        PerfLogger.begin("MarkdownWebView.updateNSView.tick")
        defer { PerfLogger.end("MarkdownWebView.updateNSView.tick") }
        let coord = context.coordinator
        PerfLogger.event(
            "MarkdownWebView.updateNSView",
            "loaded=\(coord.isLoaded) shellVersion=\(shellVersion) lastShellVersion=\(coord.lastShellVersion) bodyLen=\(bodyHTML.count) scrollRatio=\(coord.latestScrollRatio)"
        )

        if (!coord.isLoaded || coord.lastShellVersion != shellVersion) && !shellHTML.isEmpty {
            // 初回 or CSS/シェル変更時：フル HTML をリロード
            coord.isLoaded = true
            coord.lastShellVersion = shellVersion
            coord.lastBodyHTML = bodyHTML
            coord.pendingScrollRatio = coord.latestScrollRatio
            PerfLogger.begin("WebViewLoad")
            PerfLogger.event("MarkdownWebView.loadHTMLString.begin", "shellLen=\(shellHTML.count) bodyLen=\(bodyHTML.count)")
            webView.loadHTMLString(shellHTML, baseURL: URL(string: "https://kobaamd-preview.local/"))
        } else if coord.lastBodyHTML != bodyHTML {
            // 差分更新：ページナビゲーションなしでボディだけ差し替え
            coord.lastBodyHTML = bodyHTML
            coord.pendingScrollRatio = coord.latestScrollRatio
            PerfLogger.begin("MarkdownWebView.injectBody")
            PerfLogger.event("MarkdownWebView.injectBody.start", "bodyLen=\(bodyHTML.count)")
            injectBody(bodyHTML, into: webView, scrollRatio: coord.latestScrollRatio)
            PerfLogger.end("MarkdownWebView.injectBody")
        }
    }

    // MARK: - Helpers

    private func injectBody(_ body: String, into webView: WKWebView, scrollRatio: Double) {
        // body は callAsyncJavaScript の引数として安全に渡される（手動エスケープ不要）
        // functionBody は async 関数の本体として実行されるため IIFE は不要
        let js = """
        var oldScrollY = window.scrollY;
        var oldHeight = document.body.scrollHeight;
        document.body.innerHTML = body;
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
        return null;
        """
        webView.callAsyncJavaScript(
            js,
            arguments: ["body": body],
            in: nil,
            in: .page
        ) { _ in }
    }

    @MainActor class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var isLoaded = false
        var lastShellVersion: Int = 0
        var lastBodyHTML: String = ""
        var pendingScrollRatio: Double = 0
        var latestScrollRatio: Double
        weak var webView: WKWebView?
        private var previewScrollObserver: Any?
        private var blockObserver: Any?
        private var pdfObserver: Any?
        private lazy var scrollSyncThrottle = ScrollSyncThrottle { [weak self] ratio, source in
            self?.flushSyncScroll(ratio: ratio, source: source)
        }

        init(appViewModel: AppViewModel) {
            latestScrollRatio = appViewModel.previewScrollRatio
            super.init()
            previewScrollObserver = NotificationCenter.default.addObserver(
                forName: .previewScrollRatioChanged,
                object: nil,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,
                          let ratio = note.userInfo?["ratio"] as? Double else { return }
                    let source = note.userInfo?["source"] as? String ?? "unknown"
                    self.latestScrollRatio = ratio
                    self.pendingScrollRatio = ratio
                    guard self.isLoaded, self.webView != nil else { return }
                    self.scheduleSyncScroll(ratio: ratio, source: source)
                }
            }
            blockObserver = NotificationCenter.default.addObserver(
                forName: .cursorBlockChanged,
                object: nil,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,
                          let line = note.userInfo?["sourceLine"] as? Int,
                          let wv = self.webView else { return }
                    self.highlightBySourceLine(line, in: wv)
                }
            }
            pdfObserver = NotificationCenter.default.addObserver(
                forName: .exportPDFWithURL,
                object: nil,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,
                          let url = note.object as? URL else { return }
                    self.exportPDF(to: url) { result in
                        NotificationCenter.default.post(
                            name: .exportPDFCompleted,
                            object: result as AnyObject
                        )
                    }
                }
            }
        }

        deinit {
            if let previewScrollObserver { NotificationCenter.default.removeObserver(previewScrollObserver) }
            if let blockObserver { NotificationCenter.default.removeObserver(blockObserver) }
            if let pdfObserver { NotificationCenter.default.removeObserver(pdfObserver) }
        }

        func scheduleSyncScroll(ratio: Double, source: String) {
            scrollSyncThrottle.schedule(ratio: ratio, source: source)
        }

        private func flushSyncScroll(ratio: Double, source: String) {
            guard let webView else { return }
            let js = "window.scrollTo(0, \(ratio) * Math.max(document.body.scrollHeight - window.innerHeight, 0));"
            webView.evaluateJavaScript(js) { _, error in
                let detail: String
                if let error {
                    detail = "status=error error=\(error.localizedDescription)"
                } else {
                    detail = "status=applied"
                }
                PerfLogger.event(
                    "MarkdownWebView.syncScroll",
                    "source=\(source) ratio=\(ratio) \(detail)"
                )
            }
        }

        func exportPDF(to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
            guard let wv = webView else {
                completion(.failure(NSError(domain: "kobaamd", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "WebViewが見つかりません"])))
                return
            }
            let config = WKPDFConfiguration()
            wv.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url, options: .atomic)
                        DispatchQueue.main.async { completion(.success(())) }
                    } catch {
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            PerfLogger.end("WebViewLoad")
            let js = "window.scrollTo(0, \(pendingScrollRatio) * Math.max(document.body.scrollHeight - window.innerHeight, 0));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "previewLineSelected" else { return }
            let line: Int?
            if let dict = message.body as? [String: Any] {
                line = dict["line"] as? Int
            } else {
                line = nil
            }
            guard let line, let wv = webView else { return }
            highlightBySourceLine(line, in: wv, scrollIfNeeded: false)
            NotificationCenter.default.post(
                name: .jumpToLine,
                object: nil,
                userInfo: ["line": line, "source": "preview"]
            )
        }

        private func highlightBySourceLine(
            _ cursorLine: Int,
            in wv: WKWebView,
            scrollIfNeeded: Bool = true
        ) {
            let js = """
            (function(cursorLine, scrollIfNeeded) {
              document.querySelectorAll('[data-koba-active]').forEach(function(el) {
                el.removeAttribute('data-koba-active');
              });
              var blocks = document.querySelectorAll('[data-source-line-start]');
              var best = null;
              var bestStart = -1;
              for (var i = 0; i < blocks.length; i++) {
                var start = parseInt(blocks[i].dataset.sourceLineStart, 10);
                var end   = parseInt(blocks[i].dataset.sourceLineEnd,   10);
                if (start <= cursorLine && cursorLine <= end && start >= bestStart) {
                  best = blocks[i];
                  bestStart = start;
                }
              }
              if (!best) {
                for (var i = 0; i < blocks.length; i++) {
                  var start = parseInt(blocks[i].dataset.sourceLineStart, 10);
                  if (start <= cursorLine) { best = blocks[i]; }
                  else { break; }
                }
              }
              if (best) {
                best.setAttribute('data-koba-active', '');
                if (scrollIfNeeded) {
                  var rect = best.getBoundingClientRect();
                  if (rect.top < 0 || rect.bottom > window.innerHeight) {
                    best.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  }
                }
              }
            })(\(cursorLine), \(scrollIfNeeded ? "true" : "false"));
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
