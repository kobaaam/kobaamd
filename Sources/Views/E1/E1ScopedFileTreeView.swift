import SwiftUI

// MARK: - Worktree-scoped file tree (KMD-223)

struct E1ScopedFileTreeView: View {
    @Bindable var fileTreeViewModel: FileTreeViewModel
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                Text("Files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kobaInk)
                if let path = fileTreeViewModel.rootURL {
                    Text(path.lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.kobaAccent)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if fileTreeViewModel.folders.isEmpty {
                Text("セッションを選択してください")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
            } else if fileTreeViewModel.isLoading, fileTreeViewModel.nodes.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("読み込み中…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kobaMute)
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
            } else if fileTreeViewModel.nodes.isEmpty {
                Text("このフォルダに表示できるファイルがありません")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
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