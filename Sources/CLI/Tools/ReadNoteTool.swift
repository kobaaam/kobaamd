import Foundation

struct ReadNoteTool {
    static let description: JSONValue = .object([
        "name": .string("read_note"),
        "description": .string("Read a note, including frontmatter, headings, and body text."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Vault-relative or absolute path to a Markdown note inside the vault.")
                ]),
                "range": .object([
                    "type": .string("object"),
                    "description": .string("Optional body line range to return."),
                    "properties": .object([
                        "startLine": .object(["type": .string("integer")]),
                        "endLine": .object(["type": .string("integer")])
                    ])
                ])
            ]),
            "required": .array([.string("path")])
        ])
    ])

    static func run(args: JSONValue, vaultRoot: URL) async throws -> JSONValue {
        let object = try MCPToolSupport.parseArguments(args)
        let path = try MCPToolSupport.requiredString("path", from: object)
        let resolvedURL = try VaultPath(vaultRoot: vaultRoot).resolve(path)
        // Ensure path is a regular file (reject device files, FIFOs, symlinks, etc.)
        let resourceValues = try? resolvedURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues?.isRegularFile == true else {
            throw MCPToolError.invalidArguments("Invalid params: path is not a regular file")
        }
        let note = try MCPToolSupport.loadNote(at: resolvedURL)

        let headings = MCPToolSupport.extractHeadings(from: note.body, lineOffset: note.bodyStartLine - 1)
        let headingsJSON = JSONValue.array(
            headings.map { heading in
                .object([
                    "level": .int(heading.level),
                    "text": .string(heading.text),
                    "line": .int(heading.line)
                ])
            }
        )

        let bodyText = try bodyTextFromRange(object["range"], note: note)
        let frontmatterText = note.frontmatterText ?? ""

        return .array([
            MCPToolSupport.textContent("path: \(MCPToolSupport.relativePath(for: resolvedURL, root: vaultRoot))"),
            MCPToolSupport.textContent("title: \(note.title)"),
            MCPToolSupport.textContent("frontmatter:\n\(frontmatterText)"),
            MCPToolSupport.textContent("headings:\n\(try MCPToolSupport.encodeJSONString(headingsJSON))"),
            MCPToolSupport.textContent("body:\n\(bodyText)")
        ])
    }

    private static func bodyTextFromRange(_ rangeValue: JSONValue?, note: MCPToolSupport.NoteSummary) throws -> String {
        guard let rangeValue else {
            return note.body
        }

        guard case let .object(rangeObject) = rangeValue else {
            throw MCPToolError.invalidArguments("Invalid params: range must be an object")
        }

        guard let startLine = rangeObject["startLine"]?.intValue,
              let endLine = rangeObject["endLine"]?.intValue else {
            throw MCPToolError.invalidArguments("Invalid params: range requires startLine and endLine")
        }

        guard startLine > 0, endLine >= startLine else {
            throw MCPToolError.invalidArguments("Invalid params: range must satisfy startLine > 0 and endLine >= startLine")
        }

        let lines = note.body.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return "" }

        let lowerBound = min(startLine - 1, lines.count)
        let upperBound = min(endLine, lines.count)
        guard lowerBound < upperBound else { return "" }
        return lines[lowerBound..<upperBound].joined(separator: "\n")
    }
}
