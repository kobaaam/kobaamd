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
