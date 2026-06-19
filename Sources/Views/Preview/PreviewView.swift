import SwiftUI

struct PreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable var appState = AppState.shared
    @State private var previewViewModel = PreviewViewModel()
    // Delay WKWebView creation until there's actual content — saves ~50MB at cold start
    @State private var isReady = false
    @State private var hasReceivedFirstRender: Bool = false

    var body: some View {
        Group {
            if isD2File {
                D2PreviewView()
            } else if isCSVFile {
                CSVPreviewView()
            } else {
                ZStack {
                    if isReady {
                        MarkdownWebView(
                            appViewModel: appViewModel,
                            shellHTML: previewViewModel.shellHTML,
                            shellVersion: previewViewModel.shellVersion,
                            bodyHTML: previewViewModel.bodyHTML
                        )
                    } else {
                        Color.kobaSurface
                    }
                    if previewViewModel.isRendering && !hasReceivedFirstRender {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.7)
                                    .padding(10)
                                    .onAppear { PerfLogger.event("ProgressView(Preview).visible", "isRendering=\(previewViewModel.isRendering) hasFirst=\(hasReceivedFirstRender)") }
                                    .onDisappear { PerfLogger.event("ProgressView(Preview).hidden", "isRendering=\(previewViewModel.isRendering) hasFirst=\(hasReceivedFirstRender)") }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appViewModel.editorText) { oldValue, newValue in
            PerfLogger.event("PreviewView.editorTextChanged", "old=\(oldValue.count) new=\(newValue.count) isReady=\(isReady) hasFirst=\(hasReceivedFirstRender)")
            guard !isD2File && !isCSVFile else { return }
            let text = appViewModel.resolvedActiveFileContent()
            if !isReady && !text.isEmpty { isReady = true }
            previewViewModel.update(text: text, viewerMode: appViewModel.previewMode == .viewer)
        }
        .onChange(of: appViewModel.selectedFileURL) { _, newURL in
            // ファイル切替直後は debounce を飛ばして即時 render（preview の stale 表示回避）
            PerfLogger.event("PreviewView.selectedFileURLChanged", "url=\(newURL?.lastPathComponent ?? "nil")")
            guard !isD2File && !isCSVFile else { return }
            let text = appViewModel.resolvedActiveFileContent()
            if !text.isEmpty {
                isReady = true
                previewViewModel.updateImmediate(text: text, viewerMode: appViewModel.previewMode == .viewer)
            }
        }
        .onChange(of: appViewModel.previewMode) { _, _ in
            guard !isD2File && !isCSVFile else { return }
            previewViewModel.update(
                text: appViewModel.resolvedActiveFileContent(),
                viewerMode: appViewModel.previewMode == .viewer
            )
        }
        .onChange(of: appState.selectedTheme) { _, _ in
            guard !isD2File && !isCSVFile else { return }
            previewViewModel.update(
                text: appViewModel.resolvedActiveFileContent(),
                viewerMode: appViewModel.previewMode == .viewer
            )
        }
        .onChange(of: previewViewModel.bodyHTML) { _, newValue in
            PerfLogger.event("PreviewView.bodyHTMLChanged", "newLen=\(newValue.count) hasFirst=\(hasReceivedFirstRender)")
            if !newValue.isEmpty {
                hasReceivedFirstRender = true
            }
        }
        .onAppear {
            PerfLogger.event("PreviewView.onAppear", "isD2=\(isD2File) isCSV=\(isCSVFile) hasFirst=\(hasReceivedFirstRender) textLen=\(appViewModel.editorText.count)")
            guard !isD2File && !isCSVFile else { return }
            let text = appViewModel.resolvedActiveFileContent()
            if !text.isEmpty {
                isReady = true
                previewViewModel.update(text: text, viewerMode: appViewModel.previewMode == .viewer)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceFilesChanged)) { _ in
            guard !isD2File && !isCSVFile else { return }
            let text = appViewModel.resolvedActiveFileContent()
            guard !text.isEmpty else { return }
            isReady = true
            previewViewModel.updateImmediate(text: text, viewerMode: appViewModel.previewMode == .viewer)
        }
    }

    private var isD2File: Bool {
        appViewModel.selectedFileURL?.pathExtension.lowercased() == "d2"
    }

    private var isCSVFile: Bool {
        appViewModel.selectedFileURL?.pathExtension.lowercased() == "csv"
    }
}

struct D2PreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var d2VM = D2PreviewViewModel()

    var body: some View {
        ZStack {
            D2WebView(d2Code: d2VM.pendingCode, viewModel: d2VM)

            if let errorMessage = d2VM.errorMessage, !errorMessage.isEmpty {
                ScrollView {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            }

            if d2VM.isRendering {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .padding(10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appViewModel.editorText) { _, _ in
            d2VM.update(text: appViewModel.resolvedActiveFileContent())
        }
        .onAppear {
            d2VM.update(text: appViewModel.resolvedActiveFileContent())
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceFilesChanged)) { _ in
            d2VM.updateImmediate(text: appViewModel.resolvedActiveFileContent())
        }
    }
}
