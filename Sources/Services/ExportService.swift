import AppKit
import WebKit
import UniformTypeIdentifiers

// Exports the current document as PDF or HTML.
// Codex provided the initial structure; Claude fixed the WKNavigationDelegate
// (must be NSObject subclass, not a struct) and the async/await pattern.
@MainActor
enum ExportService {

    enum ExportError: LocalizedError {
        case userCancelled
        case pdfCreationFailed

        var errorDescription: String? {
            switch self {
            case .userCancelled:      return nil
            case .pdfCreationFailed:  return "PDFの生成に失敗しました"
            }
        }
    }

    // MARK: - Public

    static func exportPDF(html: String, suggestedName: String) async throws {
        let url = try showSavePanel(suggestedName: suggestedName, contentType: .pdf)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1200))
        try await loadHTML(in: webView, html: html)
        let config = WKPDFConfiguration()
        let data = try await withCheckedThrowingContinuation { cont in
            webView.createPDF(configuration: config) { result in
                cont.resume(with: result)
            }
        }
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    static func exportHTML(html: String, suggestedName: String) throws {
        let url = try showSavePanel(suggestedName: suggestedName, contentType: .html)
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private static func showSavePanel(suggestedName: String, contentType: UTType) throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else {
            throw ExportError.userCancelled
        }
        return url
    }

    private static func loadHTML(in webView: WKWebView, html: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = LoadDelegate(continuation: continuation)
            webView.navigationDelegate = delegate
            // Keep delegate alive for the duration of the load.
            objc_setAssociatedObject(webView, &LoadDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN)
            webView.loadHTMLString(html, baseURL: URL(string: "https://kobaamd-preview.local/"))
        }
    }
}

// MARK: - LoadDelegate

/// NSObject-based delegate required by WKNavigationDelegate (cannot use a struct).
private final class LoadDelegate: NSObject, WKNavigationDelegate {
    static var key = 0
    private let continuation: CheckedContinuation<Void, Error>
    private var resumed = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume(with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, Error>) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}
