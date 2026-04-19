import Foundation

struct SearchResult: Identifiable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    let matchLine: String
    let lineNumber: Int
}

@Observable
@MainActor
class SearchViewModel {
    var query: String = ""
    var results: [SearchResult] = []
    var isSearching: Bool = false

    func search(in rootURL: URL?) {
        guard let rootURL, !query.isEmpty else {
            results = []
            return
        }
        isSearching = true
        results = []
        let q = query
        Task {
            let found = await performSearch(rootURL: rootURL, query: q)
            self.results = found
            self.isSearching = false
        }
    }

    private func performSearch(rootURL: URL, query: String) async -> [SearchResult] {
        await Task.detached(priority: .userInitiated) {
            let lowercased = query.lowercased()
            var matches: [SearchResult] = []
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "md",
                      let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() {
                    if line.lowercased().contains(lowercased) {
                        matches.append(SearchResult(
                            id: UUID(),
                            fileURL: fileURL,
                            fileName: fileURL.lastPathComponent,
                            matchLine: line.trimmingCharacters(in: .whitespaces),
                            lineNumber: index + 1
                        ))
                    }
                }
            }
            return matches
        }.value
    }
}
