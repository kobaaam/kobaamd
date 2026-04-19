import SwiftUI

struct PreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var previewViewModel = PreviewViewModel()

    var body: some View {
        MarkdownWebView(html: previewViewModel.html)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: appViewModel.editorText) { _, newValue in
                previewViewModel.update(text: newValue)
            }
            .onAppear {
                previewViewModel.update(text: appViewModel.editorText)
            }
    }
}
