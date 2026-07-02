import Foundation
import Testing
@testable import kobaamd

@Suite("FileContentResolver")
struct FileContentResolverTests {
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    @Test("Prefers disk when clean")
    func prefersDiskWhenClean() throws {
        let file = try workspace.write("# disk", to: "note.md")

        let resolved = FileContentResolver.displayContent(
            url: file,
            inMemory: "# memory",
            isDirty: false
        )
        #expect(resolved == "# disk")
    }

    @Test("Uses memory when dirty")
    func usesMemoryWhenDirty() throws {
        let file = try workspace.write("# disk", to: "note.md")

        let resolved = FileContentResolver.displayContent(
            url: file,
            inMemory: "# editing",
            isDirty: true
        )
        #expect(resolved == "# editing")
    }
}