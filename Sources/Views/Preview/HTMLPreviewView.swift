import AppKit
import SwiftUI
import WebKit

// MARK: - HTML file preview (Chromium or WebKit via localhost)

struct HTMLPreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared
    @State private var reloadGeneration = 0
    @State private var previewHTML = ""
    @State private var previewURL: URL?
    @State private var previewError: String?

    var body: some View {
        let chrome = appState.selectedTheme
        Group {
            if previewHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 8) {
                    Text("HTML が空です")
                        .font(.callout)
                        .foregroundStyle(chrome.chromeMute)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let previewError {
                VStack(spacing: 8) {
                    Text("プレビューを開始できません")
                        .font(.callout)
                        .foregroundStyle(chrome.chromeMute)
                    Text(previewError)
                        .font(.caption)
                        .foregroundStyle(chrome.chromeMute2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if appState.htmlPreviewEngine == .chromium,
                      ChromiumPreviewController.shared.installedBrowser != nil {
                ChromiumHTMLPreviewHost(
                    previewURL: previewURL,
                    reloadGeneration: reloadGeneration
                )
            } else if let previewURL {
                LocalhostHTMLWebView(
                    previewURL: previewURL,
                    reloadGeneration: reloadGeneration
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromePaper)
        .onAppear { refreshPreview() }
        .onDisappear {
            if appState.htmlPreviewEngine == .chromium {
                ChromiumPreviewController.shared.closePreviewWindow()
            }
        }
        .onChange(of: appViewModel.selectedFileURL) { _, _ in refreshPreview() }
        .onChange(of: appViewModel.editorText) { _, _ in refreshPreview() }
        .onChange(of: appViewModel.isDirty) { _, _ in refreshPreview() }
        .onChange(of: appState.htmlPreviewEngine) { _, _ in refreshPreview() }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceFilesChanged)) { _ in
            refreshPreview(forceReload: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .htmlPreviewForceReload)) { _ in
            refreshPreview(forceReload: true)
        }
    }

    private func refreshPreview(forceReload: Bool = false) {
        previewHTML = appViewModel.resolvedActiveFileContent()
        do {
            let port = try WorkspacePreviewHTTPServer.shared.ensureStarted()
            let materialized = try HTMLPreviewMaterializer.materialize(
                fileURL: appViewModel.selectedFileURL,
                html: previewHTML,
                isDirty: appViewModel.isDirty
            )
            WorkspacePreviewHTTPServer.shared.setServeRoot(materialized.serveRoot)
            guard let url = WorkspacePreviewHTTPServer.shared.previewURL(
                path: materialized.relativePath,
                port: port
            ) else {
                previewError = "プレビュー URL を生成できませんでした。"
                previewURL = nil
                return
            }
            previewURL = url
            previewError = nil
            if forceReload {
                reloadGeneration += 1
            }
        } catch {
            previewError = error.localizedDescription
            previewURL = nil
        }
    }
}

// MARK: - Chromium host (positions Chrome/Chromium over preview pane)

private struct ChromiumHTMLPreviewHost: NSViewRepresentable {
    let previewURL: URL?
    let reloadGeneration: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ChromiumHTMLPreviewHostView {
        let view = ChromiumHTMLPreviewHostView()
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: ChromiumHTMLPreviewHostView, context: Context) {
        context.coordinator.hostView = nsView
        nsView.previewURL = previewURL
        nsView.reloadGeneration = reloadGeneration
        nsView.refresh()
    }

    final class Coordinator {
        weak var hostView: ChromiumHTMLPreviewHostView?
    }
}

@MainActor
final class ChromiumHTMLPreviewHostView: NSView {
    var previewURL: URL?
    var reloadGeneration: Int = 0

    private var lastPreviewURL: URL?
    private var lastReloadGeneration: Int = 0
    private var hasOpened = false
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.92).cgColor

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
        updateStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        guard let previewURL else { return }
        let controller = ChromiumPreviewController.shared
        let frame = screenFrame()

        let urlChanged = lastPreviewURL != previewURL
        let forceReload = reloadGeneration != lastReloadGeneration
        lastPreviewURL = previewURL
        lastReloadGeneration = reloadGeneration

        if !hasOpened || urlChanged {
            hasOpened = true
            controller.openOrNavigate(to: previewURL, in: frame)
        } else if forceReload {
            controller.reloadActivePage(in: frame)
        } else if let browser = controller.installedBrowser {
            controller.alignFrontWindow(of: browser, to: frame)
        }
        updateStatus()
    }

    override func layout() {
        super.layout()
        guard previewURL != nil,
              let browser = ChromiumPreviewController.shared.installedBrowser else { return }
        ChromiumPreviewController.shared.alignFrontWindow(of: browser, to: screenFrame())
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func viewDidHide() {
        super.viewDidHide()
        ChromiumPreviewController.shared.closePreviewWindow()
    }

    private func screenFrame() -> CGRect {
        guard let window else { return .zero }
        let rect = convert(bounds, to: nil)
        return window.convertToScreen(rect)
    }

    private func updateStatus() {
        if let browser = ChromiumPreviewController.shared.installedBrowser {
            statusLabel.stringValue = "\(browser.displayName) でプレビュー中\n（Chromium エンジン）"
        } else {
            statusLabel.stringValue = "Chromium 系ブラウザが見つかりません。\n設定で WebKit に切り替えるか、Google Chrome をインストールしてください。"
        }
    }
}

// MARK: - Navigation policy pure logic (testable)

/// HTML プレビュー WebView のナビゲーションポリシー判定ロジック。
///
/// `LocalhostHTMLWebView.Coordinator` は private なため、
/// ポリシー判定を `enum` として切り出してユニットテスト可能にする。
///
/// ## 設計判断（脅威モデル）
///
/// HTML プレビューは JS 有効が必須（CSS アニメーション・React 等の対応のため）。
/// 一方でプレビュー内のリンクやスクリプトが WebView 内で外部 URL へ遷移すると、
/// 意図せず外部コンテンツが読み込まれる。
///
/// ## ナビゲーションタイプ別の方針
///
/// - `about:` / 空スキーム: 常に allow（about:blank 等の初期フレーム）
/// - 同一 origin（scheme + host + port が一致）: 常に allow
///   （相対パスアセット・ハッシュ遷移・SPA 内ルーティング等）
/// - `previewURL == nil`（初期ロード前の安全弁）: allow
/// - 上記以外の外部 URL: navType に関わらず cancel
///   - `linkActivated`: 呼び出し側で `NSWorkspace` に委譲してからキャンセル
///   - `.other`（JS 起点: `window.location=` 等）: サイレントキャンセル
///   - `.reload` で外部 URL: cancel（正常な reload は同一 origin に留まる）
///   - `file:` / `blob:` 等の危険スキーム: cancel
///
/// 正当なインタラクティブ HTML（SPA・React・Vue 等）は同一 origin 内に留まるため
/// `.other` を外部 URL に対して cancel しても壊れない。
enum LocalhostHTMLWebViewCoordinatorPolicy {
    static func navigationPolicy(
        for url: URL,
        navigationType: WKNavigationType,
        previewURL: URL?
    ) -> WKNavigationActionPolicy {
        let scheme = url.scheme?.lowercased() ?? ""

        // about:blank / 空スキームは常に通す（初期フレーム等）
        if scheme == "about" || scheme == "" {
            return .allow
        }

        // previewURL 未設定の初期ロード安全弁 — サーバー起動前などに備える
        guard let previewURL else {
            return .allow
        }

        // 同一 origin（スキーム + ホスト + ポートが一致）内は常に allow
        // SPA のルーティング・ハッシュ遷移・相対アセット読み込みを壊さないため
        if url.scheme == previewURL.scheme,
           url.host == previewURL.host,
           url.port == previewURL.port {
            return .allow
        }

        // 同一 origin 外はナビゲーションタイプに関わらずキャンセル。
        // JS 起点（.other: window.location= 等）も外部 URL なら cancel する。
        // 正当な SPA は同一 origin に留まるため、この制限で壊れることはない。
        return .cancel
    }
}

// MARK: - WebKit fallback via localhost

private struct LocalhostHTMLWebView: NSViewRepresentable {
    let previewURL: URL
    let reloadGeneration: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.webView = webView

        let urlChanged = coordinator.lastURL != previewURL
        let forceReload = reloadGeneration != coordinator.lastReloadGeneration
        guard urlChanged || forceReload else { return }

        coordinator.lastURL = previewURL
        coordinator.lastReloadGeneration = reloadGeneration
        // 初期ロード時の baseURL（origin 判定に使用）を記録する
        coordinator.currentPreviewURL = previewURL

        if forceReload {
            URLCache.shared.removeAllCachedResponses()
            let dataStore = webView.configuration.websiteDataStore
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {
                DispatchQueue.main.async {
                    webView.load(URLRequest(url: previewURL, cachePolicy: .reloadIgnoringLocalCacheData))
                }
            }
            return
        }

        webView.load(URLRequest(url: previewURL))
    }

    // MARK: - NavigationDelegate

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL: URL?
        var lastReloadGeneration: Int = 0
        weak var webView: WKWebView?
        /// 現在のプレビューの origin（ポリシー判定の基準）
        var currentPreviewURL: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let navType = navigationAction.navigationType
            let policy = LocalhostHTMLWebViewCoordinatorPolicy.navigationPolicy(
                for: url,
                navigationType: navType,
                previewURL: currentPreviewURL
            )

            // linkActivated で外部 http/https はシステムブラウザで開く
            if navType == .linkActivated, policy == .cancel {
                let scheme = url.scheme?.lowercased() ?? ""
                if scheme == "http" || scheme == "https" {
                    NSWorkspace.shared.open(url)
                }
            }

            decisionHandler(policy)
        }
    }
}