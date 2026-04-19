import Foundation

struct FileDocument: Identifiable {
    let id: UUID
    let url: URL
    let content: String
}
