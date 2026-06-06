import SwiftUI
import WebKit

// MARK: - HTML file browser preview (WKWebView)

struct HTMLPreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared

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
                    fileURL: appViewModel.selectedFileURL
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromePaper)
    }
}

private struct HTMLFileWebView: NSViewRepresentable {
    let html: String
    let fileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let baseURL = fileURL?.deletingLastPathComponent()
        guard context.coordinator.lastHTML != html || context.coordinator.lastBaseURL != baseURL else {
            return
        }
        context.coordinator.lastHTML = html
        context.coordinator.lastBaseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator {
        var lastHTML: String = ""
        var lastBaseURL: URL?
    }
}