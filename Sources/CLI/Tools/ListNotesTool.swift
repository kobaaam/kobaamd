import Foundation

struct ListNotesTool {
    static let description: JSONValue = .object([
        "name": .string("list_notes"),
        "description": .string("List Markdown notes in the vault or under a subdirectory."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "under": .object([
                    "type": .string("string"),
                    "description": .string("Optional subdirectory under the vault root.")
                ])
            ])
        ])
    ])

    static func run(args: JSONValue, vaultRoot: URL) async throws -> JSONValue {
        let object = try MCPToolSupport.parseArguments(args)
        let under = MCPToolSupport.optionalString("under", from: object)
        let files = try MCPToolSupport.listMarkdownFiles(in: vaultRoot, under: under)
        let payload = JSONValue.array(files.map { .string(MCPToolSupport.relativePath(for: $0, root: vaultRoot)) })
        return .array([MCPToolSupport.textContent(try MCPToolSupport.encodeJSONString(payload))])
    }
}
