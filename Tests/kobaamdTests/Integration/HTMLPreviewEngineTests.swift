import Foundation
import Testing
@testable import kobaamd

@Suite("HTML preview engine")
struct HTMLPreviewEngineTests {
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    @Test("HTML preview engine defaults to chromium")
    func defaultEngineIsChromium() throws {
        let suiteName = "kobaamd.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let state = AppState(defaults: defaults)
        #expect(state.htmlPreviewEngine == .chromium)
    }

    @Test("HTML preview engine persists selection")
    func enginePersists() throws {
        let suiteName = "kobaamd.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let state = AppState(defaults: defaults)
        state.htmlPreviewEngine = .webKit
        let reloaded = AppState(defaults: defaults)
        #expect(reloaded.htmlPreviewEngine == .webKit)
    }

    @Test("Materializer writes dirty preview beside source file")
    func materializeDirtyPreview() throws {
        let source = try workspace.write("<html><body>old</body></html>", to: "page.html")

        let result = try HTMLPreviewMaterializer.materialize(
            fileURL: source,
            html: "<html><body>new</body></html>",
            isDirty: true
        )

        #expect(result.serveRoot == source.deletingLastPathComponent().standardizedFileURL)
        #expect(result.relativePath == HTMLPreviewMaterializer.swapFileName)
        let swap = workspace.url(HTMLPreviewMaterializer.swapFileName)
        #expect(FileManager.default.fileExists(atPath: swap.path))
        #expect(try String(contentsOf: swap, encoding: .utf8).contains("new"))
    }

    @Test("Materializer serves clean file directly")
    func materializeCleanPreview() throws {
        let source = try workspace.write("<html><body>clean</body></html>", to: "page.html")

        let result = try HTMLPreviewMaterializer.materialize(
            fileURL: source,
            html: "<html><body>ignored</body></html>",
            isDirty: false
        )

        #expect(result.relativePath == "page.html")
    }

    @Test("Preview URL builder encodes path")
    func previewURLBuilder() {
        let url = WorkspacePreviewHTTPServer.shared.previewURL(path: "foo/bar.html", port: 9123)
        #expect(url?.absoluteString == "http://127.0.0.1:9123/foo/bar.html")
    }

    @Test("MIME mapping covers common web assets")
    func mimeTypes() {
        #expect(WorkspacePreviewHTTPServer.mimeType(for: "html") == "text/html; charset=utf-8")
        #expect(WorkspacePreviewHTTPServer.mimeType(for: "css") == "text/css; charset=utf-8")
        #expect(WorkspacePreviewHTTPServer.mimeType(for: "js") == "text/javascript; charset=utf-8")
    }
}