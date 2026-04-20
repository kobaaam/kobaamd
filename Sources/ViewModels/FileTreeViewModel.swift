import AppKit
import Observation

@MainActor
@Observable
final class FileTreeViewModel {
    var rootURL: URL? = nil
    var nodes: [FileNode] = []
    var selectedNode: FileNode? = nil
    var isLoading: Bool = false

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
        let url = rootURL
        isLoading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let newNodes = FileService().loadNodes(at: url)
            await MainActor.run {
                self?.nodes = newNodes
                self?.isLoading = false
            }
        }
    }

    /// Creates a new .md file in the given directory with a unique name and returns its URL.
    func createNewFile(in directory: URL) throws -> URL {
        let service = FileService()
        var name = "Untitled.md"
        var counter = 1
        var target = directory.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: target.path) {
            name = "Untitled-\(counter).md"
            target = directory.appendingPathComponent(name)
            counter += 1
        }
        try service.saveFile(at: target, content: "")
        reload()
        return target
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
