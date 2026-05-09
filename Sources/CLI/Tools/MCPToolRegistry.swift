import Foundation

enum MCPToolError: Error, Sendable, Equatable {
    case unknownTool(String)
    case invalidArguments(String)
}

struct MCPToolRegistry: Sendable {
    let vaultRoot: URL

    func toolDescriptions() -> [JSONValue] {
        [
            SearchNotesTool.description,
            ReadNoteTool.description,
            ListNotesTool.description,
            GetHeadingsTool.description,
            GetBacklinksTool.description,
            GetTagsTool.description
        ]
    }

    func dispatch(toolName: String, arguments: JSONValue) async throws -> JSONValue {
        switch toolName {
        case "search_notes":
            return try await SearchNotesTool.run(args: arguments, vaultRoot: vaultRoot)
        case "read_note":
            return try await ReadNoteTool.run(args: arguments, vaultRoot: vaultRoot)
        case "list_notes":
            return try await ListNotesTool.run(args: arguments, vaultRoot: vaultRoot)
        case "get_headings":
            return try await GetHeadingsTool.run(args: arguments, vaultRoot: vaultRoot)
        case "get_backlinks":
            return try await GetBacklinksTool.run(args: arguments, vaultRoot: vaultRoot)
        case "get_tags":
            return try await GetTagsTool.run(args: arguments, vaultRoot: vaultRoot)
        default:
            throw MCPToolError.unknownTool(toolName)
        }
    }
}
