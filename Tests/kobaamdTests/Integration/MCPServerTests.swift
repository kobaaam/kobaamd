import Foundation
import Darwin
import Testing
@testable import kobaamd

@Suite("MCP Server")
struct MCPServerTests {
    let tmpDir: URL

    init() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    private func createVault(named name: String = "vault") throws -> URL {
        let vault = tmpDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func searchResults(from value: JSONValue) throws -> [[String: JSONValue]] {
        guard case let .array(content) = value,
              let payload = content.first?["text"]?.stringValue,
              let data = payload.data(using: .utf8),
              case let .array(items) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            Issue.record("Unexpected search_notes payload.")
            return []
        }
        return items.compactMap(\.objectValue)
    }

    private func rankValue(_ value: JSONValue?) -> Double? {
        switch value {
        case .int(let number):
            return Double(number)
        case .double(let number):
            return number
        default:
            return nil
        }
    }

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

    @Test("VaultPath rejects symlink pointing outside vault")
    func vaultPathRejectsFileSymlinkOutsideVault() throws {
        let vault = try createVault()
        let leak = vault.appendingPathComponent("leak.md")
        try FileManager.default.createSymbolicLink(at: leak, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))

        #expect(throws: VaultPath.Error.outsideVault) {
            try VaultPath(vaultRoot: vault).resolve("leak.md")
        }
    }

    @Test("VaultPath rejects directory symlink pointing outside vault")
    func vaultPathRejectsDirectorySymlinkOutsideVault() throws {
        let vault = try createVault()
        let outside = tmpDir.appendingPathComponent("outside_dir", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try write("secret", to: outside.appendingPathComponent("key.md"))
        try FileManager.default.createSymbolicLink(
            at: vault.appendingPathComponent("secrets"),
            withDestinationURL: outside
        )

        #expect(throws: VaultPath.Error.outsideVault) {
            try VaultPath(vaultRoot: vault).resolve("secrets/key.md")
        }
    }

    @Test("listMarkdownFiles skips symlinks within vault")
    func listMarkdownFilesSkipsSymlinkFiles() throws {
        let vault = try createVault()
        let outside = tmpDir.appendingPathComponent("outside.md")
        try write("# Outside", to: outside)
        try write("# Real", to: vault.appendingPathComponent("real.md"))
        try FileManager.default.createSymbolicLink(
            at: vault.appendingPathComponent("sym.md"),
            withDestinationURL: outside
        )

        let files = try MCPToolSupport.listMarkdownFiles(in: vault)
        let relativePaths = files.map { MCPToolSupport.relativePath(for: $0, root: vault) }

        #expect(relativePaths == ["real.md"])
    }

    @Test("listMarkdownFiles handles symlink directories")
    func listMarkdownFilesSkipsSymlinkDirectories() throws {
        let vault = try createVault()
        let subdirectory = vault.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try write("# Note", to: subdirectory.appendingPathComponent("note.md"))
        try FileManager.default.createSymbolicLink(
            at: vault.appendingPathComponent("link"),
            withDestinationURL: URL(fileURLWithPath: "sub")
        )

        let files = try MCPToolSupport.listMarkdownFiles(in: vault)
        let relativePaths = files.map { MCPToolSupport.relativePath(for: $0, root: vault) }

        #expect(relativePaths == ["sub/note.md"])
    }

    @Test("read_note rejects directory path")
    func readNoteRejectsDirectoryPath() async throws {
        let vault = try createVault()
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("dir"), withIntermediateDirectories: true)

        await #expect(throws: MCPToolError.invalidArguments("Invalid params: path is not a regular file")) {
            _ = try await ReadNoteTool.run(args: .object(["path": .string("dir")]), vaultRoot: vault)
        }
    }

    @Test("read_note rejects FIFO")
    func readNoteRejectsFIFO() async throws {
        let vault = try createVault()
        let pipeURL = vault.appendingPathComponent("pipe.md")
        let result = pipeURL.path.withCString { mkfifo($0, 0o644) }
        #expect(result == 0)

        await #expect(throws: MCPToolError.invalidArguments("Invalid params: path is not a regular file")) {
            _ = try await ReadNoteTool.run(args: .object(["path": .string("pipe.md")]), vaultRoot: vault)
        }
    }

    @Test("MCPServer responds with negotiated protocolVersion 2024-11-05")
    func mcpServerNegotiatesOlderSupportedProtocolVersion() {
        #expect(MCPServer.negotiateProtocolVersion(requested: "2024-11-05") == "2024-11-05")
    }

    @Test("MCPServer responds with 2025-06-18 for unknown version")
    func mcpServerFallsBackForUnknownProtocolVersion() {
        #expect(MCPServer.negotiateProtocolVersion(requested: "1999-01-01") == "2025-06-18")
    }

    @Test("MCPServer responds with 2025-06-18 when protocolVersion absent")
    func mcpServerFallsBackWhenProtocolVersionAbsent() {
        #expect(MCPServer.negotiateProtocolVersion(requested: nil) == "2025-06-18")
    }

    @Test("search_notes uses SQLite FTS5 BM25 ranking")
    func searchNotesUsesSQLiteRanking() async throws {
        let vault = try createVault()
        try write(
            """
            # Dense
            Mermaid 設定
            Mermaid 設定
            Mermaid 設定
            Mermaid 設定
            Mermaid 設定
            """,
            to: vault.appendingPathComponent("dense.md")
        )
        try write(
            """
            # Sparse
            Mermaid 設定
            """,
            to: vault.appendingPathComponent("sparse.md")
        )
        try write(
            """
            # Other
            Graphviz only
            """,
            to: vault.appendingPathComponent("other.md")
        )

        let value = try await SearchNotesTool.run(
            args: .object([
                "query": .string("Mermaid"),
                "limit": .int(10)
            ]),
            vaultRoot: vault
        )
        let results = try searchResults(from: value)

        #expect(results.count == 2)
        #expect(results[0]["path"] == .string("dense.md"))
        #expect(results[1]["path"] == .string("sparse.md"))
        #expect(results[0]["title"] == .string("Dense"))
        #expect(results[1]["title"] == .string("Sparse"))
        #expect(results[0]["snippet"]?.stringValue?.contains("Mermaid") == true)
        #expect(results[1]["snippet"]?.stringValue?.contains("Mermaid") == true)
        #expect(rankValue(results[0]["rank"]) != nil)
        #expect(rankValue(results[1]["rank"]) != nil)
        #expect((rankValue(results[0]["rank"]) ?? .infinity) <= (rankValue(results[1]["rank"]) ?? -.infinity))
    }
}
