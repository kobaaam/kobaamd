import Foundation

struct SearchNotesTool {
    static let description: JSONValue = .object([
        "name": .string("search_notes"),
        "description": .string("Search Markdown notes in the vault with SQLite FTS5 and BM25 ranking."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Full-text query.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum number of results to return. Default 20, max 100.")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    ])

    static func run(args: JSONValue, vaultRoot: URL) async throws -> JSONValue {
        let object = try MCPToolSupport.parseArguments(args)
        let query = try MCPToolSupport.requiredString("query", from: object)
        let requestedLimit = MCPToolSupport.optionalInt("limit", from: object) ?? 20
        guard requestedLimit > 0 else {
            throw MCPToolError.invalidArguments("Invalid params: limit must be greater than 0")
        }

        let limit = min(requestedLimit, 100)
        do {
            let index = try WikiSearchIndex(vaultRoot: vaultRoot)
            try index.rebuildIfNeeded()
            let hits = try index.search(query: query, limit: limit)
            let results = hits.map { hit in
                JSONValue.object([
                    "path": .string(hit.path),
                    "title": .string(hit.title),
                    "snippet": .string(hit.snippet),
                    "rank": .double(hit.bm25Rank)
                ])
            }
            let payload = try MCPToolSupport.encodeJSONString(.array(results))
            return .array([MCPToolSupport.textContent(payload)])
        } catch {
            throw MCPToolError.invalidArguments("search index unavailable: \(error.localizedDescription)")
        }
    }
}
