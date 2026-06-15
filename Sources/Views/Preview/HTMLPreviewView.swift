import SwiftUI
import WebKit

// MARK: - HTML file browser preview (WKWebView)

struct HTMLPreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared
    @State private var reloadGeneration = 0
    @State private var previewHTML = ""

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
            } else {
                HTMLFileWebView(
                    html: previewHTML,
                    fileURL: appViewModel.selectedFileURL,
                    reloadGeneration: reloadGeneration
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromePaper)
        .onAppear { refreshPreviewHTML() }
        .onChange(of: appViewModel.selectedFileURL) { _, _ in refreshPreviewHTML() }
        .onChange(of: appViewModel.editorText) { _, _ in refreshPreviewHTML() }
        .onChange(of: appViewModel.isDirty) { _, _ in refreshPreviewHTML() }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceFilesChanged)) { _ in
            refreshPreviewHTML()
            reloadGeneration += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .htmlPreviewForceReload)) { _ in
            refreshPreviewHTML()
            reloadGeneration += 1
        }
    }

    /// 未保存編集時はエディタバッファ、それ以外はディスクを優先（Claude Code 等の外部更新を反映）。
    private func refreshPreviewHTML() {
        if appViewModel.isDirty {
            previewHTML = appViewModel.editorText
            return
        }
        if let url = appViewModel.selectedFileURL,
           let disk = try? FileService().readFile(at: url) {
            previewHTML = disk
            return
        }
        previewHTML = appViewModel.editorText
    }
}

private struct HTMLFileWebView: NSViewRepresentable {
    let html: String
    let fileURL: URL?
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
        let baseURL = fileURL?.deletingLastPathComponent()
        let coordinator = context.coordinator
        coordinator.webView = webView

        let contentChanged = coordinator.lastHTML != html || coordinator.lastBaseURL != baseURL
        let forceReload = reloadGeneration != coordinator.lastReloadGeneration

        guard contentChanged || forceReload else { return }

        if forceReload {
            coordinator.lastReloadGeneration = reloadGeneration
            coordinator.reloadIgnoringCache(html: html, baseURL: baseURL)
            return
        }

        coordinator.lastHTML = html
        coordinator.lastBaseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator {
        var lastHTML: String = ""
        var lastBaseURL: URL?
        var lastReloadGeneration: Int = 0
        weak var webView: WKWebView?

        func reloadIgnoringCache(html: String, baseURL: URL?) {
            guard let webView else { return }
            URLCache.shared.removeAllCachedResponses()
            let dataStore = webView.configuration.websiteDataStore
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, let webView = self.webView else { return }
                    self.lastHTML = html
                    self.lastBaseURL = baseURL
                    webView.loadHTMLString(html, baseURL: baseURL)
                }
            }
        }
    }
}