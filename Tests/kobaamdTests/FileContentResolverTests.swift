import Foundation
import Testing
@testable import kobaamd

@Suite("FileContentResolver")
struct FileContentResolverTests {
    @Test("Prefers disk when clean")
    func prefersDiskWhenClean() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("note.md")
        try "# disk".write(to: file, atomically: true, encoding: .utf8)

        let resolved = FileContentResolver.displayContent(
            url: file,
            inMemory: "# memory",
            isDirty: false
        )
        #expect(resolved == "# disk")
    }

    @Test("Uses memory when dirty")
    func usesMemoryWhenDirty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("note.md")
        try "# disk".write(to: file, atomically: true, encoding: .utf8)

        let resolved = FileContentResolver.displayContent(
            url: file,
            inMemory: "# editing",
            isDirty: true
        )
        #expect(resolved == "# editing")
    }
}