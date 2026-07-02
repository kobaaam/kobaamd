import Foundation
import Network
import Testing
@testable import kobaamd

/// DNS rebinding 対策: WorkspacePreviewHTTPServer の Host ヘッダ検証を
/// 実サーバー起動 + NWConnection で検証する統合テスト。
///
/// テスト戦略:
/// - 正常な Host（127.0.0.1:PORT）→ Host 検証通過で serveRoot 未設定 503
/// - 偽 Host（evil.example.com）→ 403 Forbidden
/// - Host ヘッダ欠落（HTTP/1.0 風リクエスト）→ 403 Forbidden
/// - 有効 Host + 実ファイル + serveRoot 設定済み → 200 OK
@Suite("Preview HTTP server Host validation")
struct PreviewHostValidationTests {

    // MARK: - isAllowedHost 純関数テスト

    @Test("127.0.0.1 は許可されること")
    func localhost127IsAllowed() {
        #expect(WorkspacePreviewHTTPServer.isAllowedHost("127.0.0.1", port: 9000))
    }

    @Test("localhost は許可されること")
    func localhostNameIsAllowed() {
        #expect(WorkspacePreviewHTTPServer.isAllowedHost("localhost", port: 9000))
    }

    @Test("127.0.0.1:PORT 形式は許可されること")
    func localhostWithPortIsAllowed() {
        #expect(WorkspacePreviewHTTPServer.isAllowedHost("127.0.0.1:9000", port: 9000))
    }

    @Test("localhost:PORT 形式は許可されること")
    func localhostNameWithPortIsAllowed() {
        #expect(WorkspacePreviewHTTPServer.isAllowedHost("localhost:9000", port: 9000))
    }

    @Test("[::1] は許可されること")
    func ipv6LoopbackIsAllowed() {
        #expect(WorkspacePreviewHTTPServer.isAllowedHost("[::1]", port: 9000))
    }

    @Test("外部ホスト名は拒否されること")
    func externalHostIsRejected() {
        #expect(!WorkspacePreviewHTTPServer.isAllowedHost("evil.example.com", port: 9000))
    }

    @Test("DNS rebinding 風ホスト名は拒否されること")
    func dnsRebindingHostIsRejected() {
        #expect(!WorkspacePreviewHTTPServer.isAllowedHost("127.0.0.1.evil.example.com", port: 9000))
    }

    @Test("大文字 LOCALHOST は許可されること（大文字小文字非依存）")
    func localhostCaseInsensitive() {
        #expect(WorkspacePreviewHTTPServer.isAllowedHost("LOCALHOST", port: 9000))
    }

    // MARK: - 実サーバーテスト（NWConnection 使用）

    @Test("正常 Host は Host 検証を通過し、serveRoot 未設定なら 503 を返す")
    func validHostGets503WhenNoRoot() async throws {
        let server = WorkspacePreviewHTTPServer()
        let port = try server.ensureStarted()
        defer { server.stop() }

        let status = try await rawHTTPGet(
            path: "/nonexistent.html",
            host: "127.0.0.1:\(port)",
            port: port
        )
        #expect(status == 503, "有効な Host なら 403 ではなく root 未設定 503 になるはず、got \(status)")
    }

    @Test("偽 Host は 403 を返す")
    func fakeHostGets403() async throws {
        let server = WorkspacePreviewHTTPServer()
        let port = try server.ensureStarted()
        defer { server.stop() }

        let status = try await rawHTTPGet(
            path: "/index.html",
            host: "evil.example.com",
            port: port
        )
        #expect(status == 403, "DNS rebinding 風ホストは 403 になるはず、got \(status)")
    }

    @Test("Host ヘッダ欠落は 403 を返す")
    func missingHostGets403() async throws {
        let server = WorkspacePreviewHTTPServer()
        let port = try server.ensureStarted()
        defer { server.stop() }

        let status = try await rawHTTPGetNoHost(
            path: "/index.html",
            port: port
        )
        #expect(status == 403, "Host ヘッダ欠落は 403 になるはず、got \(status)")
    }

    @Test("正規ファイルは 200 を返す（有効 Host + 実ファイル + serveRoot 設定）")
    func validRequestReturns200() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("test.html")
        try "<html><body>hello</body></html>".write(to: file, atomically: true, encoding: .utf8)

        let server = WorkspacePreviewHTTPServer()
        let port = try server.ensureStarted()
        defer { server.stop() }
        server.setServeRoot(root)

        let status = try await rawHTTPGet(
            path: "/test.html",
            host: "127.0.0.1:\(port)",
            port: port
        )
        #expect(status == 200, "有効なリクエストは 200 になるはず、got \(status)")
    }
}

// MARK: - テスト用 HTTP ヘルパー（NWConnection）

/// NWConnection を使って生 HTTP/1.1 リクエストを送り、レスポンスのステータスコードを返す。
/// URLSession は Host ヘッダを自動付与するため、Host ヘッダを制御するには低レベルAPIが必要。
private func rawHTTPGet(path: String, host: String, port: UInt16) async throws -> Int {
    let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
    return try await sendRawTCPRequest(request, port: port)
}

/// Host ヘッダを含まない HTTP/1.0 風リクエストを送る。
private func rawHTTPGetNoHost(path: String, port: UInt16) async throws -> Int {
    let request = "GET \(path) HTTP/1.0\r\nConnection: close\r\n\r\n"
    return try await sendRawTCPRequest(request, port: port)
}

private func sendRawTCPRequest(_ requestString: String, port: UInt16) async throws -> Int {
    return try await withCheckedThrowingContinuation { continuation in
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "test.nw.\(UUID().uuidString)")

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let data = Data(requestString.utf8)
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        connection.cancel()
                        continuation.resume(throwing: error)
                        return
                    }
                    // レスポンス受信
                    connection.receive(minimumIncompleteLength: 12, maximumLength: 4096) { data, _, _, error in
                        connection.cancel()
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let data,
                              let responseString = String(data: data, encoding: .utf8),
                              let statusLine = responseString.split(separator: "\r\n").first,
                              let statusStr = statusLine.split(separator: " ").dropFirst().first,
                              let statusCode = Int(statusStr) else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                            return
                        }
                        continuation.resume(returning: statusCode)
                    }
                })
            case .failed(let error):
                continuation.resume(throwing: error)
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}
