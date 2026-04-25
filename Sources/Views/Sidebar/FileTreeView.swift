import SwiftUI

struct FileTreeView: View {
    @Bindable var fileTreeViewModel: FileTreeViewModel
    @Environment(AppViewModel.self) private var appViewModel

    @State private var renamingNode: FileNode? = nil
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var deletingNode: FileNode? = nil
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        List {
            // ── Add Folder to Workspace ───────────────────────────
            Button {
                fileTreeViewModel.addFolder()
            } label: {
                Label("フォルダをワークスペースに追加", systemImage: "folder.badge.plus")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kobaMute)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, 2)

            ForEach($fileTreeViewModel.folders) { $folder in
                FolderSection(
                    folder: $folder,
                    fileTreeViewModel: fileTreeViewModel,
                    renamingNode: $renamingNode,
                    showRenameAlert: $showRenameAlert,
                    renameText: $renameText,
                    deletingNode: $deletingNode,
                    showDeleteConfirm: $showDeleteConfirm,
                    onSelect: select,
                    onRemove: { fileTreeViewModel.removeFolder(id: folder.id) }
                )
            }

            // 空きエリア（右クリックでワークスペース操作メニュー）
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 60)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button {
                        fileTreeViewModel.addFolder()
                    } label: {
                        Label("フォルダをワークスペースに追加", systemImage: "folder.badge.plus")
                    }
                }
        }
        .listStyle(.sidebar)
        .alert("名前を変更", isPresented: $showRenameAlert) {
            TextField("新しい名前", text: $renameText)
            Button("変更") { renameNode() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(renamingNode?.name ?? "")
        }
        .confirmationDialog("削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("ゴミ箱に移動", role: .destructive) { deleteNode() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(deletingNode?.name ?? "")
        }
    }

    private func select(node: FileNode) {
        guard !node.isDirectory else { return }
        fileTreeViewModel.selectedNode = node
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

    private func renameNode() {
        guard let node = renamingNode, !renameText.isEmpty else { return }
        let newURL = node.url.deletingLastPathComponent().appendingPathComponent(renameText)
        do {
            try FileManager.default.moveItem(at: node.url, to: newURL)
            if appViewModel.selectedFileURL == node.url {
                appViewModel.selectedFileURL = newURL
            }
            fileTreeViewModel.reload()
        } catch {
            appViewModel.showAppError(.fileRenameFailed(from: node.url, to: newURL, underlying: error))
        }
    }

    private func deleteNode() {
        guard let node = deletingNode else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            fileTreeViewModel.reload()
        } catch {
            appViewModel.showAppError(.fileDeleteFailed(url: node.url, underlying: error))
        }
    }
}

// MARK: - Per-folder section

private struct FolderSection: View {
    @Binding var folder: WorkspaceFolder
    var fileTreeViewModel: FileTreeViewModel
    @Binding var renamingNode: FileNode?
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String
    @Binding var deletingNode: FileNode?
    @Binding var showDeleteConfirm: Bool
    var onSelect: (FileNode) -> Void
    var onRemove: () -> Void

    @Environment(AppViewModel.self) private var appViewModel
    @State private var isHoveringHeader = false

    var body: some View {
        Section(isExpanded: $folder.isExpanded) {
            OutlineGroup(folder.nodes, id: \.id, children: \.children) { node in
                NodeRow(
                    node: node,
                    fileTreeViewModel: fileTreeViewModel,
                    renamingNode: $renamingNode,
                    showRenameAlert: $showRenameAlert,
                    renameText: $renameText,
                    deletingNode: $deletingNode,
                    showDeleteConfirm: $showDeleteConfirm,
                    onSelect: onSelect
                )
            }
        } header: {
            HStack(spacing: 4) {
                Text(folder.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.kobaMute2)
                    .lineLimit(1)
                    .help((folder.url.path as NSString).abbreviatingWithTildeInPath)
                Spacer()
                if isHoveringHeader {
                    // 新規ファイル
                    Button {
                        do {
                            let url = try fileTreeViewModel.createNewFile(in: folder.url)
                            appViewModel.selectedFileURL = url
                            appViewModel.editorText = ""
                            appViewModel.markSaved()
                            AppState.saveLastFile(url)
                        } catch {
                            appViewModel.showAppError(.fileWriteFailed(url: folder.url, underlying: error))
                        }
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kobaMute)
                    }
                    .buttonStyle(.plain)
                    .help("新規ファイル")

                    // フォルダを削除
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kobaMute)
                    }
                    .buttonStyle(.plain)
                    .help("ワークスペースから削除")
                }
            }
            .padding(.vertical, 2)
            .onHover { isHoveringHeader = $0 }
        }
    }
}

// MARK: - Node row

private struct NodeRow: View {
    let node: FileNode
    var fileTreeViewModel: FileTreeViewModel
    @Binding var renamingNode: FileNode?
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String
    @Binding var deletingNode: FileNode?
    @Binding var showDeleteConfirm: Bool
    var onSelect: (FileNode) -> Void

    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        Label(node.name, systemImage: node.isDirectory ? "folder" : iconName(for: node.url))
            .lineLimit(1)
            .font(.system(size: 12))
            .foregroundStyle(Color.kobaInk)
            .onTapGesture {
                guard !node.isDirectory else { return }
                onSelect(node)
            }
            .contextMenu {
                if node.isDirectory {
                    Button {
                        do {
                            let newURL = try fileTreeViewModel.createNewFile(in: node.url)
                            appViewModel.selectedFileURL = newURL
                            appViewModel.editorText = ""
                            appViewModel.markSaved()
                            AppState.saveLastFile(newURL)
                            renamingNode = FileNode(name: newURL.lastPathComponent,
                                                    url: newURL,
                                                    isDirectory: false,
                                                    children: nil)
                            renameText = newURL.lastPathComponent
                            showRenameAlert = true
                        } catch {
                            appViewModel.showAppError(.fileWriteFailed(url: node.url, underlying: error))
                        }
                    } label: {
                        Label("新規ファイル...", systemImage: "doc.badge.plus")
                    }
                }
                Button {
                    renamingNode = node
                    renameText = node.name
                    showRenameAlert = true
                } label: {
                    Label("名前を変更...", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deletingNode = node
                    showDeleteConfirm = true
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "doc.text"
        case "swift":          return "swift"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        case "html", "css", "scss", "xml": return "globe"
        case "sh", "zsh", "bash": return "terminal"
        case "py":             return "doc.text.below.echelon"
        default:               return "doc"
        }
    }
}
