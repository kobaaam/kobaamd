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

    final class Coordinator {
        var lastURL: URL?
        var lastReloadGeneration: Int = 0
        weak var webView: WKWebView?
    }
}