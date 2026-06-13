import SwiftUI

// MARK: - E1 viewer path bar (direct file path input)

struct E1ViewerPathBar: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared

    @State private var draftPath = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let chrome = appState.selectedTheme
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(chrome.chromeMute2)

            TextField("ファイルパスを入力 (Enter で開く)", text: $draftPath)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(chrome.chromeInk)
                .focused($isFocused)
                .onSubmit { submitPath() }
                .onKeyPress(.escape) {
                    syncFromSelection()
                    isFocused = false
                    return .handled
                }

            if appViewModel.isDirty {
                Circle()
                    .fill(Color.kobaAccent)
                    .frame(width: 5, height: 5)
                    .help("未保存の変更あり")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(chrome.chromeSurface)
        .overlay(KobaHDivider(), alignment: .bottom)
        .onAppear { syncFromSelection() }
        .onChange(of: appViewModel.selectedFileURL) { _, _ in
            guard !isFocused else { return }
            syncFromSelection()
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { syncFromSelection() }
        }
    }

    private func syncFromSelection() {
        draftPath = appViewModel.selectedFileURL?.path ?? ""
    }

    private func submitPath() {
        guard let url = resolveInput(draftPath) else {
            syncFromSelection()
            isFocused = false
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            appViewModel.showAppError(.fileReadFailed(
                url: url,
                underlying: NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileNoSuchFileError,
                    userInfo: [NSLocalizedDescriptionKey: "ファイルが見つかりません"]
                )
            ))
            syncFromSelection()
            isFocused = false
            return
        }

        guard FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            appViewModel.showAppError(.fileReadFailed(
                url: url,
                underlying: NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnsupportedSchemeError,
                    userInfo: [NSLocalizedDescriptionKey: "対応していないファイル形式です"]
                )
            ))
            syncFromSelection()
            isFocused = false
            return
        }

        if !appViewModel.quickOpenViewModel.isWithinScope(url) {
            appViewModel.showAppError(.fileReadFailed(
                url: url,
                underlying: NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoPermissionError,
                    userInfo: [NSLocalizedDescriptionKey: "このセッションのワークスペース外のファイルです"]
                )
            ))
            syncFromSelection()
            isFocused = false
            return
        }

        isFocused = false
        Task { await appViewModel.openFile(url: url) }
    }

    private func resolveInput(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url.standardizedFileURL
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }

        if let root = appViewModel.fileTreeViewModel.rootURL {
            return root.appendingPathComponent(expanded).standardizedFileURL
        }

        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
}