import SwiftUI

struct FileTreeView: View {
    var fileTreeViewModel: FileTreeViewModel
    @Environment(AppViewModel.self) private var appViewModel

    @State private var listSelection: FileNode? = nil
    @State private var renamingNode: FileNode? = nil
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var deletingNode: FileNode? = nil
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        Group {
            if fileTreeViewModel.nodes.isEmpty {
                Text("No folder opened")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $listSelection) {
                    OutlineGroup(fileTreeViewModel.nodes, id: \.id, children: \.children) { node in
                        let isSelected = listSelection?.url == node.url
                        Label(node.name, systemImage: node.isDirectory ? "folder" : iconName(for: node.url))
                            .lineLimit(1)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? Color.kobaAccent : Color.kobaInk)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .tag(node)
                            .onTapGesture {
                                guard !node.isDirectory else { return }
                                listSelection = node
                                select(node: node)
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
                                            let newFileNode = FileNode(name: newURL.lastPathComponent,
                                                                       url: newURL,
                                                                       isDirectory: false,
                                                                       children: nil)
                                            renamingNode = newFileNode
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
                }
                .listStyle(.sidebar)
            }
        }
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
