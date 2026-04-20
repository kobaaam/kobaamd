import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var showFindReplace: Bool = false
    @State private var showAIPanel:    Bool = false
    @State private var scrollRatio: Double = 0
    @State private var autoSaveTask: Task<Void, Never>? = nil

    var body: some View {
        @Bindable var vm = appViewModel
        VStack(spacing: 0) {
            ZStack {
                NSTextViewWrapper(binding: $vm.editorText, scrollRatio: $scrollRatio)
                    .background(Color.kobaPaper)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if appViewModel.isFileLoading {
                    Color.kobaPaper.opacity(0.6)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
                        Task.detached {
                            if let content = try? FileService().readFile(at: url) {
                                await MainActor.run {
                                    appViewModel.openInTab(url: url, content: content)
                                }
                            }
                        }
                    }
                    return true
                }

            if showFindReplace {
                Rectangle().fill(Color.kobaLine).frame(height: 1)
                FindReplaceBar(isVisible: $showFindReplace, text: $vm.editorText)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showAIPanel {
                AIAssistPanel(isVisible: $showAIPanel, editorText: $vm.editorText)
                    .frame(width: 400)
                    .padding(16)
            }
        }
        .onChange(of: scrollRatio) { _, r in
            appViewModel.previewScrollRatio = r
        }
        .onChange(of: vm.editorText) { _, _ in
            appViewModel.markEdited()
            scheduleAutoSave()
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
        .onReceive(NotificationCenter.default.publisher(for: .aiAssistRequested)) { _ in
            showAIPanel.toggle()
        }
    }

    private func scheduleAutoSave() {
        guard appViewModel.selectedFileURL != nil else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { saveCurrentFile() }
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
