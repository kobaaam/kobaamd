import Foundation
import Testing
@testable import kobaamd

@Suite("MCP Server")
struct MCPServerTests {
    @Test("VaultPath rejects traversal outside vault")
    func vaultPathRejectsTraversal() throws {
        let root = URL(fileURLWithPath: "/tmp/vault").standardizedFileURL
        let vaultPath = VaultPath(vaultRoot: root)

        #expect(throws: VaultPath.Error.outsideVault) {
            try vaultPath.resolve("../escape.md")
        }
    }

    @Test("MCPToolRegistry throws for unknown tool")
    func registryRejectsUnknownTool() async {
        let registry = MCPToolRegistry(vaultRoot: URL(fileURLWithPath: "/tmp/vault"))

        await #expect(throws: MCPToolError.unknownTool("unknown_tool")) {
            _ = try await registry.dispatch(toolName: "unknown_tool", arguments: .object([:]))
        }
    }

    @Test("JSONRPCRequest decodes id and params")
    func requestDecodes() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_notes","arguments":{"under":"docs"}}}"#.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)

        #expect(request.jsonrpc == "2.0")
        #expect(request.method == "tools/call")
        #expect(request.id == .int(1))
        #expect(request.params?["name"] == .string("list_notes"))
        #expect(request.params?["arguments"]?["under"] == .string("docs"))
    }

    @Test("JSONRPCResponse encodes compact one-line JSON")
    func responseEncodesAsOneLineJSON() throws {
        let response = JSONRPCResponse(
            jsonrpc: "2.0",
            id: .int(1),
            result: .object(["ok": .bool(true)]),
            error: nil
        )

        let data = try JSONEncoder().encode(response)
        let encoded = try #require(String(data: data, encoding: .utf8))

        #expect(!encoded.contains("\n"))
        #expect(encoded.contains(#""jsonrpc":"2.0""#))
        #expect(encoded.contains(#""id":1"#))
        #expect(encoded.contains(#""result":{"ok":true}"#))
    }
}
