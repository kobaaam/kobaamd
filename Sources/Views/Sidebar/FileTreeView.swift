import SwiftUI

struct FileTreeView: View {
    var fileTreeViewModel: FileTreeViewModel
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        Group {
            if fileTreeViewModel.nodes.isEmpty {
                Text("No folder opened")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    OutlineGroup(fileTreeViewModel.nodes, id: \.id, children: \.children) { node in
                        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture { select(node: node) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func select(node: FileNode) {
        fileTreeViewModel.selectedNode = node
        guard !node.isDirectory else {
            appViewModel.editorText = ""
            appViewModel.selectedFileURL = nil
            return
        }
        appViewModel.selectedFileURL = node.url
        Task {
            do {
                let content = try FileService().readFile(at: node.url)
                await MainActor.run {
                    appViewModel.editorText = content
                    appViewModel.markSaved()
                }
            } catch {
                await MainActor.run {
                    appViewModel.showAppError(.fileReadFailed(url: node.url, underlying: error))
                }
            }
        }
    }
}
