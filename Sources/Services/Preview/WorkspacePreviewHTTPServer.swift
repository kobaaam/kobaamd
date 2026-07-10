import Foundation
import Network

/// Serves workspace files over loopback HTTP so Chromium / WebKit can load previews
/// with Chrome-like origin semantics (relative CSS/JS, `file://` quirks avoided).
final class WorkspacePreviewHTTPServer: @unchecked Sendable {
    static let shared = WorkspacePreviewHTTPServer()

    private let queue = DispatchQueue(label: "com.kobaamd.preview-http", qos: .userInitiated)
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var serveRoot: URL?
    private let lock = NSLock()

    /// `shared` シングルトン以外のインスタンスはテスト専用。
    init() {}

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listener != nil
    }

    func currentPort() -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return port
    }

    func setServeRoot(_ url: URL) {
        lock.lock()
        serveRoot = url.standardizedFileURL
        lock.unlock()
    }

    @discardableResult
    func ensureStarted() throws -> UInt16 {
        lock.lock()
        if listener != nil, port > 0 {
            let existing = port
            lock.unlock()
            return existing
        }
        lock.unlock()

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        let semaphore = DispatchSemaphore(value: 0)
        final class PortBox: @unchecked Sendable {
            var value: UInt16 = 0
            var error: Error?
        }
        let portBox = PortBox()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard let rawPort = listener.port?.rawValue else {
                    portBox.error = PreviewServerError.portUnavailable
                    semaphore.signal()
                    return
                }
                portBox.value = rawPort
                semaphore.signal()
            case .failed(let error):
                portBox.error = error
                semaphore.signal()
            case .cancelled:
                portBox.error = PreviewServerError.cancelled
                semaphore.signal()
            default:
                break
            }
        }

        listener.start(queue: queue)
        semaphore.wait()

        if let error = portBox.error {
            listener.cancel()
            throw error
        }

        lock.lock()
        self.listener = listener
        self.port = portBox.value
        lock.unlock()
        return portBox.value
    }

    func stop() {
        lock.lock()
        listener?.cancel()
        listener = nil
        port = 0
        serveRoot = nil
        lock.unlock()
    }

    func previewURL(path: String, port: UInt16) -> URL? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return URL(string: "http://127.0.0.1:\(port)/") }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/" + trimmed
        return components.url
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // MARK: - Host ヘッダ検証

    /// DNS rebinding 攻撃を防ぐため、リクエストの Host ヘッダが
    /// 127.0.0.1 / localhost / [::1] のいずれかであることを強制する。
    /// HTTP/1.0 など Host ヘッダが無い場合も 403 を返す。
    ///
    /// 設計判断: サーバーは 127.0.0.1 にのみバインドしているが、
    /// ブラウザが DNS rebinding で attacker.example.com を 127.0.0.1 に
    /// 解決した場合、Host ヘッダには "attacker.example.com" が入る。
    /// この検証でそのリクエストを弾くことで経路を完全に塞ぐ。
    ///
    /// ポート一致は検証しない: サーバーは 127.0.0.1 のランダムポートに
    /// バインドするため、ポートを知っているクライアントは正規のアクセスと見なせる。
    /// ホスト名の正規化だけで DNS rebinding 対策として十分。
    static func isAllowedHost(_ host: String) -> Bool {
        // ポート部分を除去する。
        // IPv4 / hostname: "127.0.0.1:9000" → lastIndex(":") でポートを切り離す。
        // IPv6: "[::1]:9000" → "]" の直後の ":PORT" を切り離す。
        //        "[::1]" はそのまま。
        let hostWithoutPort: String
        if host.hasPrefix("[") {
            // IPv6 ブラケット形式 — "]" 以降のポート部分を除去
            if let closeBracket = host.lastIndex(of: "]") {
                let afterBracket = host.index(after: closeBracket)
                if afterBracket < host.endIndex, host[afterBracket] == ":" {
                    // "[::1]:port" → "[::1]"
                    hostWithoutPort = String(host[host.startIndex...closeBracket])
                } else {
                    // "[::1]" → そのまま
                    hostWithoutPort = host
                }
            } else {
                hostWithoutPort = host
            }
        } else if let colonIndex = host.lastIndex(of: ":") {
            // IPv4 / hostname: "127.0.0.1:PORT" or "localhost:PORT"
            hostWithoutPort = String(host[host.startIndex..<colonIndex])
        } else {
            hostWithoutPort = host
        }
        let lower = hostWithoutPort.lowercased()
        return lower == "127.0.0.1" || lower == "localhost" || lower == "[::1]"
    }

    private func response(for request: String) -> Data {
        // Host ヘッダ検証を最初に実施 — DNS rebinding 対策。
        // GET チェックより前に置く: 不正 Host のリクエストはメソッドに関わらず 403 で弾き、
        // 405 等の内部詳細を一切漏らさない。HTTP/1.1 では Host 必須。
        let allLines = request.components(separatedBy: "\r\n")
        let hostHeader = allLines.first(where: { $0.lowercased().hasPrefix("host:") })
        guard let hostHeader else {
            return httpResponse(status: 403, body: "Forbidden: missing Host header")
        }
        let hostValue = hostHeader
            .dropFirst("host:".count)
            .trimmingCharacters(in: .whitespaces)
        guard Self.isAllowedHost(hostValue) else {
            return httpResponse(status: 403, body: "Forbidden: invalid Host")
        }

        guard let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else {
            return httpResponse(status: 400, body: "Bad Request")
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return httpResponse(status: 405, body: "Method Not Allowed")
        }

        let rawPath = String(parts[1])
        guard let path = rawPath.split(separator: "?").first else {
            return httpResponse(status: 400, body: "Bad Request")
        }

        lock.lock()
        let root = serveRoot
        lock.unlock()

        guard let root else {
            return httpResponse(status: 503, body: "Preview root not configured")
        }

        let decoded = String(path).removingPercentEncoding ?? String(path)
        let relative = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        // シンボリックリンクを解決してからプレフィックス検証し、
        // symlink 越えの path traversal を防止する。
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        let resolvedRoot = root.resolvingSymlinksInPath()
        guard resolvedCandidate.path.hasPrefix(resolvedRoot.path + "/")
                || resolvedCandidate.path == resolvedRoot.path else {
            return httpResponse(status: 403, body: "Forbidden")
        }

        guard FileManager.default.fileExists(atPath: resolvedCandidate.path),
              let data = try? Data(contentsOf: resolvedCandidate) else {
            return httpResponse(status: 404, body: "Not Found")
        }

        let mime = Self.mimeType(for: resolvedCandidate.pathExtension)
        return httpDataResponse(status: 200, mimeType: mime, data: data)
    }

    private func httpResponse(status: Int, body: String) -> Data {
        let statusText: String
        switch status {
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Error"
        }
        let payload = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        return Data(payload.utf8)
    }

    private func httpDataResponse(status: Int, mimeType: String, data: Data) -> Data {
        let header = """
        HTTP/1.1 \(status) OK\r
        Content-Type: \(mimeType)\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r
        """
        var response = Data(header.utf8)
        response.append(data)
        return response
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "map": return "application/json; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

enum PreviewServerError: LocalizedError {
    case portUnavailable
    case cancelled
    case missingFile

    var errorDescription: String? {
        switch self {
        case .portUnavailable: return "Preview HTTP port is unavailable."
        case .cancelled: return "Preview HTTP server was cancelled."
        case .missingFile: return "Preview file is missing."
        }
    }
}

enum HTMLPreviewMaterializer {
    static let swapFileName = ".kobaamd-preview.html"

    /// プレビューサーバーに渡す serveRoot と相対パスを生成する。
    ///
    /// ## 配信範囲の設計判断
    ///
    /// serveRoot は常に「対象ファイルが存在するディレクトリ」（fileURL.deletingLastPathComponent()）
    /// または一時ディレクトリ（fileURL == nil の場合）になる。
    /// ワークスペースルートや上位ディレクトリが serveRoot になることは **構造上ありえない**。
    ///
    /// この設計はディレクトリ配信を維持しつつ配信範囲を最小化する。
    /// HTML ファイルが同ディレクトリ内の CSS/JS/画像を相対パスで参照するケースを
    /// 壊さずに、上位ファイルツリーへのアクセスを防止する。
    ///
    /// - Note: serveRoot は `WorkspacePreviewHTTPServer` の traversal チェック
    ///   （symlink 解決 + prefix 検証）と組み合わせて二重に保護される。
    static func materialize(
        fileURL: URL?,
        html: String,
        isDirty: Bool
    ) throws -> (serveRoot: URL, relativePath: String) {
        guard let fileURL else {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("kobaamd-preview", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let target = root.appendingPathComponent("index.html")
            try html.write(to: target, atomically: true, encoding: .utf8)
            return (root, "index.html")
        }

        // serveRoot = ファイルの親ディレクトリ（ワークスペースルートより広くならない保証）
        let directory = fileURL.deletingLastPathComponent().standardizedFileURL
        if isDirty {
            let swap = directory.appendingPathComponent(swapFileName)
            try html.write(to: swap, atomically: true, encoding: .utf8)
            return (directory, swapFileName)
        }
        return (directory, fileURL.lastPathComponent)
    }
}
