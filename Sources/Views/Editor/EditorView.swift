import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var scrollRatio: Double = 0

    var body: some View {
        @Bindable var vm = appViewModel
        NSTextViewWrapper(binding: $vm.editorText, scrollRatio: $scrollRatio)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: scrollRatio) { _, r in
                appViewModel.previewScrollRatio = r
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
                saveCurrentFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newFileRequested)) { _ in
                createNewFile()
            }
    }

    private func saveCurrentFile() {
        guard let url = appViewModel.selectedFileURL else {
            saveAs()
            return
        }
        do {
            try FileService().saveFile(at: url, content: appViewModel.editorText)
            appViewModel.markSaved()
        } catch {
            appViewModel.showAppError(.fileWriteFailed(url: url, underlying: error))
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        if let mdType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [mdType]
        }
        panel.nameFieldStringValue = "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileService().saveFile(at: url, content: appViewModel.editorText)
            appViewModel.selectedFileURL = url
            appViewModel.markSaved()
        } catch {
            appViewModel.showAppError(.fileWriteFailed(url: url, underlying: error))
        }
    }

    private func createNewFile() {
        appViewModel.editorText = ""
        appViewModel.savedText = ""
        appViewModel.isDirty = false
        appViewModel.selectedFileURL = nil
    }
}
