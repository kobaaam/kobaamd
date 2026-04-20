import SwiftUI

struct PreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var previewViewModel = PreviewViewModel()
    // Delay WKWebView creation until there's actual content — saves ~50MB at cold start
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                MarkdownWebView(html: previewViewModel.html, scrollRatio: appViewModel.previewScrollRatio)
            } else {
                Color.kobaSurface  // lightweight placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appViewModel.editorText) { _, newValue in
            if !isReady && !newValue.isEmpty { isReady = true }
            previewViewModel.update(text: newValue)
        }
        .onAppear {
            if !appViewModel.editorText.isEmpty {
                isReady = true
                previewViewModel.update(text: appViewModel.editorText)
            }
        }
    }
}
