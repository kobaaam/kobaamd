import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var showFindReplace: Bool = false
    @State private var scrollRatio: Double = 0   // reserved for future scroll-sync

    var editorHeader: String {
        guard let url = appViewModel.selectedFileURL else { return "No file open" }
        return url.lastPathComponent
    }

    var body: some View {
        @Bindable var vm = appViewModel
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Text(editorHeader)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(appViewModel.selectedFileURL == nil
                        ? Color.kobaMute : Color.kobaInk)
                if appViewModel.isDirty {
                    Circle()
                        .fill(Color.kobaAccent)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Text("\(appViewModel.lineCount) lines")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.kobaMute2)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color.kobaSurface)
            .overlay(
                Rectangle().fill(Color.kobaLine).frame(height: 1),
                alignment: .bottom
            )

            NSTextViewWrapper(binding: $vm.editorText, scrollRatio: $scrollRatio)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showFindReplace {
                Rectangle().fill(Color.kobaLine).frame(height: 1)
                FindReplaceBar(isVisible: $showFindReplace, text: $vm.editorText)
            }
        }
        .onChange(of: vm.editorText) { _, _ in
            appViewModel.markEdited()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
            saveCurrentFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFileRequested)) { _ in
            createNewFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findRequested)) { _ in
            showFindReplace.toggle()
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
        showFindReplace = false
    }
}
