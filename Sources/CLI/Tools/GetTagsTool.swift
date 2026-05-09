import Foundation

struct GetTagsTool {
    static let description: JSONValue = .object([
        "name": .string("get_tags"),
        "description": .string("Return vault tags with counts or files for a specific tag."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "tag": .object([
                    "type": .string("string"),
                    "description": .string("Optional tag name to filter by.")
                ])
            ])
        ])
    ])

    static func run(args: JSONValue, vaultRoot: URL) async throws -> JSONValue {
        let object = try MCPToolSupport.parseArguments(args)
        let requestedTag = MCPToolSupport.optionalString("tag", from: object)
        let files = try MCPToolSupport.listMarkdownFiles(in: vaultRoot)

        var tagsToFiles: [String: Set<String>] = [:]

        for fileURL in files {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let split = Frontmatter.split(text: content)
            guard let yaml = split.frontmatterText else { continue }

            let frontmatter = Frontmatter.parse(yaml: yaml)
            let relativePath = MCPToolSupport.relativePath(for: fileURL, root: vaultRoot)
            for tag in frontmatter.tags where !tag.isEmpty {
                tagsToFiles[tag, default: []].insert(relativePath)
            }
        }

        if let requestedTag, !requestedTag.isEmpty {
            let filesForTag = (tagsToFiles[requestedTag] ?? []).sorted()
            let payload = JSONValue.array(filesForTag.map(JSONValue.string))
            return .array([MCPToolSupport.textContent(try MCPToolSupport.encodeJSONString(payload))])
        }

        let payload = JSONValue.array(
            tagsToFiles.keys.sorted().map { tag in
                let files = Array(tagsToFiles[tag] ?? []).sorted()
                return .object([
                    "tag": .string(tag),
                    "count": .int(files.count),
                    "files": .array(files.map(JSONValue.string))
                ])
            }
        )

        return .array([MCPToolSupport.textContent(try MCPToolSupport.encodeJSONString(payload))])
    }
}
