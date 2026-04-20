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
final class SearchViewModel {
    var query: String = ""
    var results: [SearchResult] = []
    var isSearching: Bool = false
    private var searchTask: Task<Void, Never>? = nil

    func search(in rootURL: URL?) {
        guard let rootURL, !query.isEmpty else {
            results = []
            return
        }
        searchTask?.cancel()
        isSearching = true
        results = []
        let q = query
        searchTask = Task {
            let found = await performSearch(rootURL: rootURL, query: q)
            guard !Task.isCancelled else { return }
            self.results = found
            self.isSearching = false
        }
    }

    private func performSearch(rootURL: URL, query: String) async -> [SearchResult] {
        await Task.detached(priority: .userInitiated) {
            let lowercased = query.lowercased()
            let maxResults = 100
            var matches: [SearchResult] = []
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            let allURLs = enumerator.compactMap { $0 as? URL }
            outer: for fileURL in allURLs {
                guard FileService.supportedExtensions.contains(fileURL.pathExtension.lowercased()),
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
                        if matches.count >= maxResults { break outer }
                    }
                }
            }
            return matches
        }.value
    }
}
