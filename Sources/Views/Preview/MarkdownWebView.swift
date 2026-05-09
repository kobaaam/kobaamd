import SwiftUI
import WebKit

@MainActor
final class ScrollSyncDebouncer {
    /// `interval` 間隔の throttle (leading + trailing)。
    /// 連続スクロール中も `interval` ごとに flush するため、preview 側がスムーズに追従する。
    /// `delay` は後方互換用エイリアス（コンストラクタ引数として保持）。
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
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.flushPending() }
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

    @MainActor class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded = false
        var lastShellVersion: Int = 0
        var lastBodyHTML: String = ""
        var pendingScrollRatio: Double = 0
        var latestScrollRatio: Double
        weak var webView: WKWebView?
        private var previewScrollObserver: Any?
        private var blockObserver: Any?
        private var pdfObserver: Any?
        private lazy var scrollSyncDebouncer = ScrollSyncDebouncer { [weak self] ratio, source in
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
            scrollSyncDebouncer.schedule(ratio: ratio, source: source)
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
