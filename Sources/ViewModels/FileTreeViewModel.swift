import AppKit
import Observation

@MainActor
@Observable
final class FileTreeViewModel {
    var rootURL: URL? = nil
    var nodes: [FileNode] = []
    var selectedNode: FileNode? = nil

    func openFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        rootURL = url
        reload()
    }

    func reload() {
        guard let rootURL else { return }
        nodes = FileService().loadNodes(at: rootURL)
    }
}
