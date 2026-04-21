import SwiftUI

struct PreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var previewViewModel = PreviewViewModel()
    // Delay WKWebView creation until there's actual content — saves ~50MB at cold start
    @State private var isReady = false

    var body: some View {
        Group {
            if isD2File {
                D2PreviewView()
            } else {
                ZStack {
                    if isReady {
                        MarkdownWebView(
                            shellHTML: previewViewModel.shellHTML,
                            bodyHTML: previewViewModel.bodyHTML,
                            scrollRatio: appViewModel.previewScrollRatio
                        )
                    } else {
                        Color.kobaSurface
                    }
                    if previewViewModel.isRendering {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appViewModel.editorText) { _, newValue in
            guard !isD2File else { return }
            if !isReady && !newValue.isEmpty { isReady = true }
            previewViewModel.update(text: newValue)
        }
        .onAppear {
            guard !isD2File else { return }
            if !appViewModel.editorText.isEmpty {
                isReady = true
                previewViewModel.update(text: appViewModel.editorText)
            }
        }
    }

    private var isD2File: Bool {
        appViewModel.selectedFileURL?.pathExtension.lowercased() == "d2"
    }
}

struct D2PreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var d2VM = D2PreviewViewModel()

    var body: some View {
        ZStack {
            if let errorMessage = d2VM.errorMessage, !errorMessage.isEmpty {
                ScrollView {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            } else if !d2VM.svg.isEmpty {
                D2WebView(svg: d2VM.svg)
            } else {
                Color.kobaSurface
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
        .onChange(of: appViewModel.editorText) { _, newValue in
            d2VM.update(text: newValue)
        }
        .onAppear {
            d2VM.update(text: appViewModel.editorText)
        }
    }
}
