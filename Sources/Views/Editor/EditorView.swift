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
    @State private var isDragTargeted: Bool = false

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

                if isDragTargeted {
                    Color.kobaAccent
                        .opacity(0.06)
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color.kobaAccent,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                        )
                        .padding(8)
                        .allowsHitTesting(false)

                    Text("Drop to open")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.kobaMute)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted, perform: handleDrop(providers:))

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
        .onChange(of: vm.editorText) { _, newValue in
            appViewModel.outlineViewModel.update(text: newValue)
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
        .onReceive(NotificationCenter.default.publisher(for: .aiInlineRequested)) { note in
            guard let lineContent = note.userInfo?["lineContent"] as? String else { return }
            appViewModel.startAIInlineCompletion(lineContent: lineContent)
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task {
            for provider in providers {
                guard let url = await appViewModel.loadDroppedURL(from: provider) else { continue }
                await appViewModel.openDroppedFile(url: url)
            }
        }
        return true
    }
}
