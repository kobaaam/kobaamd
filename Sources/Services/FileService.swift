import Foundation

final class FileService {
    private let fileManager = FileManager.default

    func loadNodes(at url: URL) -> [FileNode] {
        guard isDirectory(url) else { return [] }
        return children(of: url)
    }

    func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func children(of directory: URL) -> [FileNode] {
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
                    nodes.append(FileNode(id: UUID(), name: item.lastPathComponent, url: item, isDirectory: true, children: children(of: item)))
                } else if item.pathExtension.lowercased() == "md" {
                    nodes.append(FileNode(id: UUID(), name: item.lastPathComponent, url: item, isDirectory: false, children: nil))
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
}
