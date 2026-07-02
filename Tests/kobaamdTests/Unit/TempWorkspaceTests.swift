import Testing
import Foundation
@testable import kobaamd

@Suite("TempWorkspace")
struct TempWorkspaceTests {

    @Test("init creates a directory under $TMPDIR")
    func initCreatesDirectory() throws {
        let ws = try TempWorkspace()
        #expect(FileManager.default.fileExists(atPath: ws.root.path))
        #expect(ws.root.lastPathComponent.hasPrefix("kobaamd-tests-"))
    }

    @Test("write creates file with correct content")
    func writeCreatesFile() throws {
        let ws = try TempWorkspace()
        let url = try ws.write("hello", to: "notes/test.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content == "hello")
    }

    @Test("write creates intermediate directories")
    func writeCreatesIntermediateDirectories() throws {
        let ws = try TempWorkspace()
        try ws.write("deep content", to: "a/b/c/file.md")
        let url = ws.url("a/b/c/file.md")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("makeDir creates nested directory")
    func makeDirCreatesDirectory() throws {
        let ws = try TempWorkspace()
        let dir = try ws.makeDir("sub/nested")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        #expect(exists && isDir.boolValue)
    }

    @Test("url returns correct absolute path")
    func urlReturnsAbsolutePath() throws {
        let ws = try TempWorkspace()
        let u = ws.url("some/path.txt")
        #expect(u.path.hasPrefix(ws.root.path))
        #expect(u.path.hasSuffix("some/path.txt"))
    }

    @Test("deinit removes root directory")
    func deinitRemovesRootDirectory() throws {
        var capturedRoot: URL?
        do {
            let ws = try TempWorkspace()
            capturedRoot = ws.root
            #expect(FileManager.default.fileExists(atPath: ws.root.path))
        }
        if let root = capturedRoot {
            #expect(!FileManager.default.fileExists(atPath: root.path))
        }
    }
}
