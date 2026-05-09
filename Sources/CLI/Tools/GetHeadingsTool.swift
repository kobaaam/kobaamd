import Foundation

struct GetHeadingsTool {
    static let description: JSONValue = .object([
        "name": .string("get_headings"),
        "description": .string("Return the heading outline for a note."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Vault-relative or absolute path to a Markdown note inside the vault.")
                ])
            ]),
            "required": .array([.string("path")])
        ])
    ])

    static func run(args: JSONValue, vaultRoot: URL) async throws -> JSONValue {
        let object = try MCPToolSupport.parseArguments(args)
        let path = try MCPToolSupport.requiredString("path", from: object)
        let fileURL = try VaultPath(vaultRoot: vaultRoot).resolve(path)
        let note = try MCPToolSupport.loadNote(at: fileURL)

        let headings = MCPToolSupport.extractHeadings(from: note.body, lineOffset: note.bodyStartLine - 1)
        let payload = JSONValue.array(
            headings.map { heading in
                .object([
                    "level": .int(heading.level),
                    "text": .string(heading.text),
                    "line": .int(heading.line)
                ])
            }
        )

        return .array([MCPToolSupport.textContent(try MCPToolSupport.encodeJSONString(payload))])
    }
}
