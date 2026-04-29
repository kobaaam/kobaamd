import Foundation

final class FileService {
    private let fileManager = FileManager.default

    static let supportedExtensions: Set<String> = [
        "d2",
        "md", "markdown",
        "txt", "text",
        "json", "yaml", "yml", "toml",
        "swift", "py", "rb", "js", "ts", "jsx", "tsx",
        "html", "css", "scss", "xml",
        "sh", "zsh", "bash",
        "gitignore", "env", "conf", "ini", "log"
    ]

    func loadNodes(at url: URL) -> [FileNode] {
        guard isDirectory(url) else { return [] }
        return children(of: url)
    }

    func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func saveFile(at url: URL, content: String) throws {
        try Data(content.utf8).write(to: url, options: .atomic)
    }

    func createNewFile(in directory: URL, named name: String) throws -> URL {
        var targetURL = directory.appendingPathComponent(name)
        if targetURL.pathExtension.isEmpty {
            targetURL = targetURL.appendingPathExtension("md")
        }
        try saveFile(at: targetURL, content: "")
        return targetURL
    }

    func createNewFolder(in directory: URL, named name: String) throws -> URL {
        let folderURL = directory.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        return folderURL
    }

    private func children(of directory: URL, depth: Int = 0, maxDepth: Int = 5) -> [FileNode] {
        guard depth < maxDepth else { return [] }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var nodes = [FileNode]()
            for item in contents {
                guard let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory else { continue }
                if isDir {
                    nodes.append(FileNode(name: item.lastPathComponent, url: item, isDirectory: true,
                                         children: children(of: item, depth: depth + 1, maxDepth: maxDepth)))
                } else if FileService.supportedExtensions.contains(item.pathExtension.lowercased()) {
                    nodes.append(FileNode(name: item.lastPathComponent, url: item, isDirectory: false, children: nil))
                }
            }
            nodes.sort { lhs, rhs in
                if lhs.isDirectory == rhs.isDirectory {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.isDirectory && !rhs.isDirectory
            }
            return nodes
        } catch {
            return []
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    // MARK: - Templates

    /// カスタムテンプレートディレクトリ
    static let customTemplateDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/kobaamd/templates", isDirectory: true)
    }()

    /// カスタムテンプレートディレクトリを作成する（存在しなければ）
    func ensureCustomTemplateDirectory() {
        let dir = Self.customTemplateDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// ビルトイン + カスタムテンプレートを読み込む
    func loadTemplates() -> [DocumentTemplate] {
        var templates: [DocumentTemplate] = []

        // ビルトインテンプレート（Bundle から）
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("templates") {
            templates += loadTemplatesFromDirectory(url: bundleURL, isBuiltIn: true)
        }
        if templates.isEmpty, let moduleURL = Bundle.module.resourceURL?.appendingPathComponent("templates") {
            templates += loadTemplatesFromDirectory(url: moduleURL, isBuiltIn: true)
        }

        // カスタムテンプレート
        ensureCustomTemplateDirectory()
        templates += loadTemplatesFromDirectory(url: Self.customTemplateDirectory, isBuiltIn: false)

        return templates
    }

    private func loadTemplatesFromDirectory(url: URL, isBuiltIn: Bool) -> [DocumentTemplate] {
        guard fileManager.fileExists(atPath: url.path),
              let files = try? fileManager.contentsOfDirectory(
                  at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
              ) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "md" || $0.pathExtension.lowercased() == "markdown" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { fileURL -> DocumentTemplate? in
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
                let filename = fileURL.deletingPathExtension().lastPathComponent
                return DocumentTemplate.parse(filename: filename, content: content, isBuiltIn: isBuiltIn)
            }
    }
}
