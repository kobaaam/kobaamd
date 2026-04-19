import Foundation

struct Document: Identifiable {
    let id: UUID
    let url: URL
    let content: String
}
