import Foundation

enum BacklinkKind: Equatable, Sendable {
    case linked
    case unlinked
}

struct Backlink: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let line: Int
    let kind: BacklinkKind
    let snippet: String
    let matchRange: NSRange
    let matchedText: String

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        line: Int,
        kind: BacklinkKind,
        snippet: String,
        matchRange: NSRange,
        matchedText: String
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.line = line
        self.kind = kind
        self.snippet = snippet
        self.matchRange = matchRange
        self.matchedText = matchedText
    }
}
