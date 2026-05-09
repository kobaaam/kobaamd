import Foundation

struct GetBacklinksTool {
    static let description: JSONValue = .object([
        "name": .string("get_backlinks"),
        "description": .string("Return linked and unlinked mentions of a note across the vault. Each result includes kind: \"linked\" or \"unlinked\"."),
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
        let targetURL = try VaultPath(vaultRoot: vaultRoot).resolve(path)
        let files = try MCPToolSupport.listMarkdownFiles(in: vaultRoot)

        var results: [JSONValue] = []

        for sourceURL in files {
            let content = try String(contentsOf: sourceURL, encoding: .utf8)
            let scanned = BacklinksScanner.scan(sourceURL: sourceURL, sourceContent: content, targetURL: targetURL)

            results.append(contentsOf: scanned.linked.map {
                .object([
                    "sourcePath": .string(MCPToolSupport.relativePath(for: $0.sourceURL, root: vaultRoot)),
                    "line": .int($0.line),
                    "snippet": .string($0.snippet),
                    "kind": .string("linked")
                ])
            })

            results.append(contentsOf: scanned.unlinked.map {
                .object([
                    "sourcePath": .string(MCPToolSupport.relativePath(for: $0.sourceURL, root: vaultRoot)),
                    "line": .int($0.line),
                    "snippet": .string($0.snippet),
                    "kind": .string("unlinked")
                ])
            })
        }

        return .array([MCPToolSupport.textContent(try MCPToolSupport.encodeJSONString(.array(results)))])
    }
}
