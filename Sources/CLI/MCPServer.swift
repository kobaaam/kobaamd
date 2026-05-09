import Foundation

actor MCPServer {
    let vaultRoot: URL
    let registry: MCPToolRegistry

    init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
        self.registry = MCPToolRegistry(vaultRoot: vaultRoot)
    }

    func run() async {
        FileHandle.standardError.write(Data("kobaamd mcp server starting (vault=\(vaultRoot.path))\n".utf8))

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vaultRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            FileHandle.standardError.write(Data("invalid vault root: \(vaultRoot.path)\n".utf8))
            return
        }

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                guard let data = line.data(using: .utf8) else { continue }
                await handleLine(data)
            }
        } catch {
            FileHandle.standardError.write(Data("mcp loop error: \(error)\n".utf8))
        }
    }

    private func handleLine(_ data: Data) async {
        let decoder = JSONDecoder()
        let request: JSONRPCRequest

        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            writeResponse(
                JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: .null,
                    result: nil,
                    error: JSONRPCError(code: -32700, message: "Parse error")
                )
            )
            return
        }

        guard request.jsonrpc == "2.0" else {
            if request.id != nil {
                writeResponse(
                    JSONRPCResponse(
                        jsonrpc: "2.0",
                        id: request.id,
                        result: nil,
                        error: JSONRPCError(code: -32600, message: "Invalid request")
                    )
                )
            }
            return
        }

        let isNotification = request.id == nil

        switch request.method {
        case "initialize":
            let result: JSONValue = .object([
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object([
                    "tools": .object([:])
                ]),
                "serverInfo": .object([
                    "name": .string("kobaamd"),
                    "version": .string(AppVersion.semantic)
                ])
            ])
            if !isNotification {
                writeResponse(JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: result, error: nil))
            }
        case "notifications/initialized", "notifications/cancelled":
            return
        case "tools/list":
            let result: JSONValue = .object([
                "tools": .array(registry.toolDescriptions())
            ])
            if !isNotification {
                writeResponse(JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: result, error: nil))
            }
        case "tools/call":
            if !isNotification {
                await handleToolCall(request: request)
            }
        default:
            if !isNotification {
                writeResponse(
                    JSONRPCResponse(
                        jsonrpc: "2.0",
                        id: request.id,
                        result: nil,
                        error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")
                    )
                )
            }
        }
    }

    private func handleToolCall(request: JSONRPCRequest) async {
        guard case let .object(params) = request.params ?? .null,
              case let .string(toolName) = params["name"] ?? .null else {
            writeResponse(
                JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: request.id,
                    result: nil,
                    error: JSONRPCError(code: -32602, message: "Invalid params: missing name")
                )
            )
            return
        }

        let arguments = params["arguments"] ?? .object([:])

        do {
            let content = try await registry.dispatch(toolName: toolName, arguments: arguments)
            let result: JSONValue = .object([
                "content": content,
                "isError": .bool(false)
            ])
            writeResponse(JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: result, error: nil))
        } catch let error as MCPToolError {
            let jsonError: JSONRPCError
            switch error {
            case .unknownTool(let name):
                jsonError = JSONRPCError(code: -32601, message: "Unknown tool: \(name)")
            case .invalidArguments(let message):
                jsonError = JSONRPCError(code: -32602, message: message)
            }
            writeResponse(JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: nil, error: jsonError))
        } catch {
            let result: JSONValue = .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Error: \(error.localizedDescription)")
                    ])
                ]),
                "isError": .bool(true)
            ])
            writeResponse(JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: result, error: nil))
        }
    }

    private func writeResponse(_ response: JSONRPCResponse) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(response) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
