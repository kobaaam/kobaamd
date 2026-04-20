import Foundation

struct EditorTab: Identifiable, Equatable {
    let id: UUID
    var url: URL?
    var content: String
    var isDirty: Bool

    init(url: URL? = nil, content: String = "") {
        self.id = UUID()
        self.url = url
        self.content = content
        self.isDirty = false
    }

    var title: String {
        url?.lastPathComponent ?? "Untitled"
    }
}
