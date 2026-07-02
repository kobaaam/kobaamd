import Testing
@testable import kobaamd
import Foundation

@Suite("WikiIndexService")
@MainActor
struct WikiIndexServiceTests {
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    var tmpDir: URL { workspace.root }

    private func write(_ content: String, name: String) throws {
        try workspace.write(content, to: name)
    }

    private func waitForReady(_ service: WikiIndexService, attempts: Int = 40) async throws {
        for _ in 0..<attempts {
            if service.state == .ready { return }
            if case .failed(let message) = service.state {
                Issue.record("Indexing failed: \(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for index readiness.")
    }

    private func waitForFailure(_ service: WikiIndexService, attempts: Int = 40) async throws -> Bool {
        for _ in 0..<attempts {
            if case .failed = service.state {
                return true
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test("Search returns nil before indexing is prepared")
    func searchReturnsNilBeforeIndexing() async {
        let service = WikiIndexService()
        let hits = await service.search(query: "keyword")
        #expect(hits == nil)
    }

    @Test("Indexes markdown files and returns snippets")
    func indexesFilesAndSearches() async throws {
        try write("# Alpha\nこれは特定キーワードを含む本文です。", name: "alpha.md")
        try write("# Beta\n別のノートです。", name: "beta.md")
        try write("特定キーワードはここにもあります。", name: "gamma.txt")

        let service = WikiIndexService()
        service.setRoot(tmpDir)
        try await waitForReady(service)

        let indexURL = tmpDir.appendingPathComponent(".kobaamd/index.sqlite")
        #expect(FileManager.default.fileExists(atPath: indexURL.path))

        let hits = await service.search(query: "特定キーワード")
        #expect(hits != nil)
        #expect(!(hits ?? []).isEmpty)
        #expect((hits ?? []).contains { $0.snippet.contains("特定キーワード") })
    }

    @Test("Skips node_modules by default")
    func skipsNodeModulesByDefault() async throws {
        let deps = tmpDir.appendingPathComponent("node_modules/pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: deps, withIntermediateDirectories: true)
        try "秘密の依存キーワード".write(
            to: deps.appendingPathComponent("hidden.js"),
            atomically: true,
            encoding: .utf8
        )
        try write("公開キーワードはここ", name: "visible.md")

        let service = WikiIndexService()
        service.setRoot(tmpDir)
        try await waitForReady(service)

        let depHits = await service.search(query: "秘密の依存キーワード")
        #expect(depHits?.isEmpty == true)

        let visibleHits = await service.search(query: "公開キーワード")
        #expect(visibleHits?.isEmpty == false)
    }

    @Test("Skips .kobaamd internal directory during indexing")
    func skipsKobaamdInternalDirectory() async throws {
        let internalDir = tmpDir.appendingPathComponent(".kobaamd", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        try "内部ログキーワード".write(
            to: internalDir.appendingPathComponent("transcript.log"),
            atomically: true,
            encoding: .utf8
        )
        try write("外部キーワード", name: "visible.md")

        let service = WikiIndexService()
        service.setRoot(tmpDir)
        try await waitForReady(service)

        let internalHits = await service.search(query: "内部ログキーワード")
        #expect(internalHits?.isEmpty == true)

        let externalHits = await service.search(query: "外部キーワード")
        #expect(externalHits?.isEmpty == false)
    }

    @Test("Repeated setRoot while building does not restart")
    func setRootIgnoresDuplicateWhileBuilding() async throws {
        try write("検索対象ワード", name: "note.md")

        let service = WikiIndexService()
        service.setRoot(tmpDir)
        #expect(service.state == .building)
        service.setRoot(tmpDir)
        #expect(service.state == .building)
        try await waitForReady(service)
    }

    @Test("Index build failure moves state to failed")
    func indexingFailureSetsFailedState() async throws {
        let blockedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: blockedRoot, withIntermediateDirectories: true)
        let blocker = blockedRoot.appendingPathComponent(".kobaamd")
        try "block".write(to: blocker, atomically: true, encoding: .utf8)

        let service = WikiIndexService()
        service.setRoot(blockedRoot)

        let didFail = try await waitForFailure(service)
        #expect(didFail)
        if case .failed = service.state {
            #expect(true)
        } else {
            Issue.record("Expected failed state but found \(service.state).")
        }
    }
}
