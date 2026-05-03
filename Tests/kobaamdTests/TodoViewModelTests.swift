import Testing
@testable import kobaamd
import Foundation

@Suite("TodoViewModel")
@MainActor
struct TodoViewModelTests {
    let tmpDir: URL

    init() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    private func write(_ content: String, name: String, in dir: URL? = nil) throws -> URL {
        let target = (dir ?? tmpDir).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    private func waitForItems(_ vm: TodoViewModel, attempts: Int = 40) async throws {
        for _ in 0..<attempts {
            if !vm.items.isEmpty && !vm.isScanning { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("Parse TODO from inline text (file scope, no fileURL)")
    func parsesInlineTodos() async {
        let vm = TodoViewModel()
        let items = await vm.extractTodos(from: "# Title\nTODO: write docs\nbody\nFIXME: bug here\n")
        #expect(items.count == 2)
        #expect(items.contains { $0.label == "TODO" && $0.text == "write docs" && $0.line == 2 })
        #expect(items.contains { $0.label == "FIXME" && $0.text == "bug here" && $0.line == 4 })
        #expect(items.allSatisfy { $0.fileURL == nil })
    }

    @Test("HTML comment TODOs are detected")
    func parsesHtmlCommentTodos() async {
        let vm = TodoViewModel()
        let items = await vm.extractTodos(from: "<!-- TODO: hidden note -->\nrest")
        #expect(items.count == 1)
        #expect(items.first?.text == "hidden note")
    }

    @Test("scanDirectory collects TODOs from .md files in directory")
    func scanDirectoryCollectsMd() async throws {
        _ = try write("TODO: alpha\n", name: "a.md")
        _ = try write("FIXME: beta\n", name: "sub/b.md")
        _ = try write("TODO: ignored\n", name: "c.txt")
        let items = await TodoViewModel.scanDirectory(at: tmpDir)
        #expect(items.contains { $0.text == "alpha" })
        #expect(items.contains { $0.text == "beta" })
        #expect(!items.contains { $0.text == "ignored" })
        #expect(items.allSatisfy { $0.fileURL != nil })
    }

    @Test("scanWorkspace collects TODOs from multiple roots")
    func scanWorkspaceMerges() async throws {
        let dirA = tmpDir.appendingPathComponent("A")
        let dirB = tmpDir.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        _ = try write("TODO: from-a\n", name: "x.md", in: dirA)
        _ = try write("FIXME: from-b\n", name: "y.md", in: dirB)
        let items = await TodoViewModel.scanWorkspace(folders: [dirA, dirB])
        #expect(items.contains { $0.text == "from-a" })
        #expect(items.contains { $0.text == "from-b" })
    }

    @Test("Scope switch triggers reload (file -> folder -> file)")
    func scopeSwitchReloads() async throws {
        let vm = TodoViewModel()
        vm.update(text: "TODO: file-only\n")
        try await Task.sleep(for: .milliseconds(400))
        #expect(vm.items.contains { $0.text == "file-only" })

        _ = try write("TODO: folder-found\n", name: "x.md")
        vm.updateFolderRoot(tmpDir)
        vm.setScope(.folder)
        try await waitForItems(vm)
        #expect(vm.items.contains { $0.text == "folder-found" })
        #expect(!vm.items.contains { $0.text == "file-only" })

        vm.setScope(.file)
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.items.contains { $0.text == "file-only" })
    }

    @Test("maxDepth=5 limits descent")
    func maxDepthLimits() async throws {
        let deepDir = tmpDir
            .appendingPathComponent("d1/d2/d3/d4/d5/d6", isDirectory: true)
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        try "TODO: too-deep\n".write(
            to: deepDir.appendingPathComponent("x.md"),
            atomically: true,
            encoding: .utf8
        )
        try "TODO: shallow\n".write(
            to: tmpDir.appendingPathComponent("d1/y.md"),
            atomically: true,
            encoding: .utf8
        )
        let items = await TodoViewModel.scanDirectory(at: tmpDir, maxDepth: 5)
        #expect(items.contains { $0.text == "shallow" })
        #expect(!items.contains { $0.text == "too-deep" })
    }
}
