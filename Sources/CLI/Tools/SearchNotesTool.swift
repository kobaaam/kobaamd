import Foundation

struct SearchNotesTool {
    static let description: JSONValue = .object([
        "name": .string("search_notes"),
        "description": .string("Search Markdown notes in the vault and return matching lines."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Case-insensitive text query.")
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
        let files = try MCPToolSupport.listMarkdownFiles(in: vaultRoot)
        var results: [JSONValue] = []
        results.reserveCapacity(limit)

        for fileURL in files {
            if results.count >= limit { break }

            let note = try MCPToolSupport.loadNote(at: fileURL)
            let lines = note.body.components(separatedBy: .newlines)

            for (index, line) in lines.enumerated() {
                if results.count >= limit { break }
                guard line.range(of: query, options: .caseInsensitive) != nil else { continue }

                results.append(
                    .object([
                        "path": .string(MCPToolSupport.relativePath(for: fileURL, root: vaultRoot)),
                        "title": .string(note.title),
                        "snippetLine": .string(MCPToolSupport.makeSnippet(from: line)),
                        "lineNumber": .int(index + note.bodyStartLine)
                    ])
                )
            }
        }

        let payload = try MCPToolSupport.encodeJSONString(.array(results))
        return .array([MCPToolSupport.textContent(payload)])
    }
}
