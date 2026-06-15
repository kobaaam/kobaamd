import SwiftUI
import WebKit

// MARK: - HTML file browser preview (WKWebView)

struct HTMLPreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared
    @State private var reloadGeneration = 0

    var body: some View {
        let chrome = appState.selectedTheme
        Group {
            if appViewModel.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 8) {
                    Text("HTML が空です")
                        .font(.callout)
                        .foregroundStyle(chrome.chromeMute)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HTMLFileWebView(
                    html: appViewModel.editorText,
                    fileURL: appViewModel.selectedFileURL,
                    reloadGeneration: reloadGeneration
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromePaper)
        .onReceive(NotificationCenter.default.publisher(for: .htmlPreviewForceReload)) { _ in
            reloadGeneration += 1
        }
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