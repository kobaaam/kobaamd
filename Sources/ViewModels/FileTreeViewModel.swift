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
        AppState.saveLastFolder(url)
        reload()
    }

    func openFolder(url: URL) {
        rootURL = url
        AppState.saveLastFolder(url)
        reload()
    }

    func restoreLastFolder() {
        guard let url = AppState.loadLastFolder(),
              FileManager.default.fileExists(atPath: url.path) else { return }
        rootURL = url
        reload()
    }

    func reload() {
        guard let rootURL else { return }
        nodes = FileService().loadNodes(at: rootURL)
    }

    /// Creates a new .md file in rootURL with a unique name and returns its URL.
    func createNewFileInRoot() throws -> URL {
        guard let rootURL else {
            throw NSError(domain: "kobaamd", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No folder open"])
        }
        let service = FileService()
        var name = "Untitled.md"
        var counter = 1
        var target = rootURL.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: target.path) {
            name = "Untitled-\(counter).md"
            target = rootURL.appendingPathComponent(name)
            counter += 1
        }
        try service.saveFile(at: target, content: "")
        reload()
        return target
    }
}
