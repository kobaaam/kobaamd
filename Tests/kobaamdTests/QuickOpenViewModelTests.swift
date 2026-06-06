import Foundation
import Testing
@testable import kobaamd

@Suite("QuickOpenViewModel")
@MainActor
struct QuickOpenViewModelTests {

    private func makeVM(withFileNames fileNames: [String]) throws -> QuickOpenViewModel {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-quick-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        for fileName in fileNames {
            let fileURL = tmpDir.appendingPathComponent(fileName)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try Data().write(to: fileURL)
        }

        let folder = WorkspaceFolder(url: tmpDir, nodes: FileService().loadNodes(at: tmpDir))
        let vm = QuickOpenViewModel()
        vm.indexFiles(from: [folder])
        return vm
    }

    @Test("query が空のときは全件を返し、最大20件に制限される")
    func emptyQueryReturnsFirst20() throws {
        let vm = try makeVM(withFileNames: (1...25).map { "file\($0).md" })

        vm.query = ""
        vm.filter()

        #expect(vm.candidates.count == 20)
        #expect(vm.selectedIndex == 0)
    }

    @Test("query は fileName に対して大文字小文字を無視してフィルタされる")
    func filterMatchesFileNameCaseInsensitively() throws {
        let vm = try makeVM(withFileNames: ["Readme.md", "notes.txt", "docs/guide.md"])

        vm.query = "read"
        vm.filter()

        #expect(vm.candidates.count == 1)
        #expect(vm.candidates.first?.fileName == "Readme.md")
        #expect(vm.selectedItem?.url.lastPathComponent == "Readme.md")
    }

    @Test("scopedTo は指定ルート配下のファイルのみインデックスする")
    func scopedIndexFiltersOutsideRoot() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-qo-scope-\(UUID().uuidString)", isDirectory: true)
        let session = parent.appendingPathComponent("session", isDirectory: true)
        let other = parent.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        try Data().write(to: session.appendingPathComponent("in-scope.md"))
        try Data().write(to: other.appendingPathComponent("out-scope.md"))

        let sessionFolder = WorkspaceFolder(url: session, nodes: FileService().loadNodes(at: session))
        let otherFolder = WorkspaceFolder(url: other, nodes: FileService().loadNodes(at: other))
        let vm = QuickOpenViewModel()
        vm.indexFiles(from: [sessionFolder, otherFolder], scopedTo: session)

        vm.query = ""
        vm.filter()
        #expect(vm.candidates.count == 1)
        #expect(vm.candidates.first?.fileName == "in-scope.md")
        #expect(vm.isWithinScope(session.appendingPathComponent("in-scope.md")))
        #expect(!vm.isWithinScope(other.appendingPathComponent("out-scope.md")))
    }

    @Test("selectNext / selectPrev は端でクランプされる")
    func selectionNavigationClampsAtEdges() throws {
        let vm = try makeVM(withFileNames: ["a.md", "b.md", "c.md"])

        vm.filter()
        vm.selectNext()
        vm.selectNext()
        vm.selectNext()
        #expect(vm.selectedIndex == 2)

        vm.selectPrev()
        vm.selectPrev()
        vm.selectPrev()
        #expect(vm.selectedIndex == 0)
    }
}
