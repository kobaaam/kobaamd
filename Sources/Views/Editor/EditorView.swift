import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        @Bindable var vm = appViewModel
        NSTextViewWrapper(binding: $vm.editorText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            appViewModel.errorMessage = error.localizedDescription
            appViewModel.showError = true
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
            appViewModel.errorMessage = error.localizedDescription
            appViewModel.showError = true
        }
    }

    private func createNewFile() {
        appViewModel.editorText = ""
        appViewModel.savedText = ""
        appViewModel.isDirty = false
        appViewModel.selectedFileURL = nil
    }
}
