import AppKit
import Observation

// MARK: - Workspace folder model

struct WorkspaceFolder: Identifiable {
    let id: UUID
    var url: URL
    var nodes: [FileNode]
    var isExpanded: Bool

    init(url: URL, nodes: [FileNode] = [], isExpanded: Bool = true) {
        self.id = UUID()
        self.url = url
        self.nodes = nodes
        self.isExpanded = isExpanded
    }

    var displayName: String { url.lastPathComponent }
}

extension WorkspaceFolder: Equatable {
    static func == (lhs: WorkspaceFolder, rhs: WorkspaceFolder) -> Bool {
        lhs.id == rhs.id &&
        lhs.url == rhs.url &&
        lhs.nodes == rhs.nodes &&
        lhs.isExpanded == rhs.isExpanded
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class FileTreeViewModel {
    var folders: [WorkspaceFolder] = []
    var selectedNode: FileNode? = nil
    var isLoading: Bool = false
    /// ツリー上で NEW バッジを付けるファイル（KMD-228）
    var newFilePaths: Set<String> = []

    private let fsWatcher = WorkspaceFSEventWatcher()

    // MARK: - Legacy compat

    var rootURL: URL? { folders.first?.url }
    var nodes: [FileNode] { folders.first?.nodes ?? [] }

    // MARK: - Add / Remove

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFolder(url: url)
    }

    func addFolder(url: URL) {
        if let existing = folders.first(where: { $0.url == url }) {
            reloadFolder(id: existing.id)
            return
        }
        let folder = WorkspaceFolder(url: url)
        folders.append(folder)
        saveWorkspace()
        reloadFolder(id: folder.id)
        updateFilesystemWatching()
        NotificationCenter.default.post(name: .workspaceRootChanged, object: url)
    }

    func removeFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        saveWorkspace()
        updateFilesystemWatching()
    }

    // MARK: - Reload

    func reloadFolder(id: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        let url = folders[idx].url
        isLoading = true
        let showHiddenFiles = AppState.shared.showHiddenFiles
        let includeDependencyDirectories = AppState.shared.indexDependencyDirectories
        Task.detached(priority: .userInitiated) { [weak self] in
            let newNodes = FileService().loadNodes(
                at: url,
                showHiddenFiles: showHiddenFiles,
                includeDependencyDirectories: includeDependencyDirectories
            )
            await MainActor.run {
                guard let self,
                      let i = self.folders.firstIndex(where: { $0.id == id }) else { return }
                self.folders[i].nodes = newNodes
                self.isLoading = false
            }
        }
    }

    func reload() {
        for folder in folders { reloadFolder(id: folder.id) }
    }

    // MARK: - Persistence

    func saveWorkspace() {
        AppState.saveWorkspaceFolders(folders.map(\.url))
    }

    func restoreWorkspace() {
        let urls = AppState.loadWorkspaceFolders()
        folders = urls.map { WorkspaceFolder(url: $0) }
        for folder in folders { reloadFolder(id: folder.id) }
        updateFilesystemWatching()
        if let first = folders.first {
            NotificationCenter.default.post(name: .workspaceRootChanged, object: first.url)
        }
    }

    // MARK: - E1 scoped worktree (KMD-223)

    /// active worktree のみをワークスペースにする（セッション切替用）。
    func setScopedWorktree(_ url: URL) {
        selectedNode = nil
        newFilePaths = []
        let folder = WorkspaceFolder(url: url)
        folders = [folder]
        AppState.saveLastFolder(url)
        reloadFolder(id: folder.id)
        updateFilesystemWatching()
        NotificationCenter.default.post(name: .workspaceRootChanged, object: url)
    }

    func clearWorkspace() {
        folders = []
        selectedNode = nil
        isLoading = false
        newFilePaths = []
        fsWatcher.stop()
    }

    func markFileAsNew(_ url: URL) {
        newFilePaths.insert(url.standardizedFileURL.path)
    }

    func clearNewMark(for url: URL) {
        newFilePaths.remove(url.standardizedFileURL.path)
    }

    func isNewFile(_ url: URL) -> Bool {
        newFilePaths.contains(url.standardizedFileURL.path)
    }

    // MARK: - File operations

    func createNewFile(in directory: URL) throws -> URL {
        let target = uniqueNewFileURL(in: directory)
        try FileService().saveFile(at: target, content: "")
        markFileAsNew(target)
        if let folder = folders.first(where: { directory.path.hasPrefix($0.url.path) }) {
            reloadFolder(id: folder.id)
        }
        return target
    }

    func createNewFileInRoot() throws -> URL {
        guard let rootURL else {
            throw NSError(domain: "kobaamd", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No folder open"])
        }
        return try createNewFile(in: rootURL)
    }

    private func uniqueNewFileURL(in directory: URL) -> URL {
        var name = "Untitled.md"
        var counter = 1
        var target = directory.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: target.path) {
            name = "Untitled-\(counter).md"
            target = directory.appendingPathComponent(name)
            counter += 1
        }
        return target
    }

    // MARK: - Legacy shims

    func openFolder() { addFolder() }
    func openFolder(url: URL) { addFolder(url: url) }
    func restoreLastFolder() { restoreWorkspace() }

    // MARK: - Filesystem watching

    private func updateFilesystemWatching() {
        let urls = folders.map(\.url)
        fsWatcher.watch(urls: urls) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.reload()
                NotificationCenter.default.post(name: .workspaceFilesChanged, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let workspaceRootChanged = Notification.Name("workspaceRootChanged")
    static let workspaceFilesChanged = Notification.Name("workspaceFilesChanged")
}
