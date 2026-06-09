import SwiftUI

// MARK: - Worktree-scoped file tree (KMD-223)

struct E1ScopedFileTreeView: View {
    @Bindable var fileTreeViewModel: FileTreeViewModel
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared

    var body: some View {
        let chrome = appState.selectedTheme
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(chrome.chromeMute)
                Text("Files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chrome.chromeInk)
                if let path = fileTreeViewModel.rootURL {
                    Text(path.lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.kobaAccent)
                        .lineLimit(1)
                        .accessibilityIdentifier("e1.files.root")
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Toggle("隠しファイルを表示", isOn: $appState.showHiddenFiles)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
                .foregroundStyle(chrome.chromeMute)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .onChange(of: appState.showHiddenFiles) { _, _ in
                    fileTreeViewModel.reload()
                    appViewModel.refreshQuickOpenIndex()
                }

            if fileTreeViewModel.folders.isEmpty {
                Text("セッションを選択してください")
                    .font(.system(size: 11))
                    .foregroundStyle(chrome.chromeMute)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
            } else if fileTreeViewModel.isLoading, fileTreeViewModel.nodes.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("読み込み中…")
                        .font(.system(size: 11))
                        .foregroundStyle(chrome.chromeMute)
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
            } else if fileTreeViewModel.nodes.isEmpty {
                Text("このフォルダに表示できるファイルがありません")
                    .font(.system(size: 11))
                    .foregroundStyle(chrome.chromeMute)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
            } else {
                E1FileTreeList(
                    fileTreeViewModel: fileTreeViewModel,
                    appViewModel: appViewModel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// FileTreeView の選択処理のみ再利用（ワークスペース追加 UI は出さない）。
private struct E1FileTreeList: View {
    @Bindable var fileTreeViewModel: FileTreeViewModel
    let appViewModel: AppViewModel

    @State private var renamingNode: FileNode? = nil
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @FocusState private var isFileTreeFocused: Bool

    var body: some View {
        List {
            ForEach($fileTreeViewModel.folders) { $folder in
                FolderSection(
                    folder: $folder,
                    fileTreeViewModel: fileTreeViewModel,
                    renamingNode: $renamingNode,
                    showRenameAlert: $showRenameAlert,
                    renameText: $renameText,
                    deletingNode: .constant(nil),
                    showDeleteConfirm: .constant(false),
                    onSelect: select,
                    onRemove: {}
                )
            }
        }
        .listStyle(.sidebar)
        .focused($isFileTreeFocused)
        .onReceive(NotificationCenter.default.publisher(for: .e1FocusFileTree)) { _ in
            isFileTreeFocused = true
        }
    }

    private func select(node: FileNode) {
        guard !node.isDirectory else { return }
        fileTreeViewModel.selectedNode = node
        fileTreeViewModel.clearNewMark(for: node.url)
        appViewModel.isFileLoading = true
        AppState.saveLastFile(node.url)
        Task.detached {
            do {
                let content = try FileService().readFile(at: node.url)
                await MainActor.run {
                    appViewModel.openInTab(url: node.url, content: content)
                    appViewModel.isFileLoading = false
                }
            } catch {
                await MainActor.run {
                    appViewModel.isFileLoading = false
                    appViewModel.showAppError(.fileReadFailed(url: node.url, underlying: error))
                }
            }
        }
    }
}