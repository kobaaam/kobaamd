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

    private init() {}

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

        let listener = try NWListener(using: .tcp, on: .any)
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

    private func response(for request: String) -> Data {
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
        guard candidate.path.hasPrefix(root.path + "/") || candidate.path == root.path else {
            return httpResponse(status: 403, body: "Forbidden")
        }

        guard FileManager.default.fileExists(atPath: candidate.path),
              let data = try? Data(contentsOf: candidate) else {
            return httpResponse(status: 404, body: "Not Found")
        }

        let mime = Self.mimeType(for: candidate.pathExtension)
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

        let directory = fileURL.deletingLastPathComponent().standardizedFileURL
        if isDirty {
            let swap = directory.appendingPathComponent(swapFileName)
            try html.write(to: swap, atomically: true, encoding: .utf8)
            return (directory, swapFileName)
        }
        return (directory, fileURL.lastPathComponent)
    }
}