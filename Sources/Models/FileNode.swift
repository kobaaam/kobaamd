import Foundation

struct FileNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [FileNode]?
}
