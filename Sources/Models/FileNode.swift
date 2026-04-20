import Foundation

struct FileNode: Identifiable, Hashable {
    // URL をIDとして使うことで reload() しても同じフォルダが同じIDを持ち
    // OutlineGroup の展開状態が維持される
    var id: URL { url }
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [FileNode]?
}
