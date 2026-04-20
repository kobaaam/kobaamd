import Testing
@testable import kobaamd
import Foundation

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {
    let tmpDir: URL

    init() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    private func write(_ content: String, name: String) throws {
        try content.write(to: tmpDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // Polls until results appear or timeout (~1s). Avoids fragile fixed Task.sleep.
    private func waitForResults(_ vm: SearchViewModel, attempts: Int = 20) async throws {
        for _ in 0..<attempts {
            if !vm.results.isEmpty { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // Polls until isSearching becomes false.
    private func waitForCompletion(_ vm: SearchViewModel, attempts: Int = 20) async throws {
        for _ in 0..<attempts {
            if !vm.isSearching { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Edge cases

    @Test("Empty query produces no results")
    func emptyQueryNoResults() {
        let vm = SearchViewModel()
        vm.query = ""
        vm.search(in: tmpDir)
        #expect(vm.results.isEmpty)
    }

    @Test("Nil root produces no results")
    func nilRootNoResults() {
        let vm = SearchViewModel()
        vm.query = "hello"
        vm.search(in: nil)
        #expect(vm.results.isEmpty)
    }

    // MARK: - Basic matching

    @Test("Finds match in .md file")
    func findsMatchInMdFile() async throws {
        try write("# Hello World\nsome content", name: "note.md")
        let vm = SearchViewModel()
        vm.query = "Hello World"
        vm.search(in: tmpDir)
        try await waitForResults(vm)
        #expect(!vm.results.isEmpty)
        #expect(vm.results.contains { $0.matchLine.contains("Hello World") })
    }

    @Test("Search is case-insensitive")
    func searchIsCaseInsensitive() async throws {
        try write("UPPERCASE CONTENT", name: "note.md")
        let vm = SearchViewModel()
        vm.query = "uppercase"
        vm.search(in: tmpDir)
        try await waitForResults(vm)
        #expect(!vm.results.isEmpty)
    }

    @Test("Line number is reported correctly")
    func lineNumberIsCorrect() async throws {
        try write("line one\nline two\nline three", name: "note.md")
        let vm = SearchViewModel()
        vm.query = "line three"
        vm.search(in: tmpDir)
        try await waitForResults(vm)
        #expect(vm.results.first?.lineNumber == 3)
    }

    @Test("File name is included in results")
    func fileNameIsReported() async throws {
        try write("match content", name: "myfile.md")
        let vm = SearchViewModel()
        vm.query = "match"
        vm.search(in: tmpDir)
        try await waitForResults(vm)
        #expect(vm.results.first?.fileName == "myfile.md")
    }

    // MARK: - Extension filtering

    @Test("Unsupported extensions are ignored")
    func ignoresUnsupportedExtensions() async throws {
        try write("hello world", name: "doc.docx")
        try write("hello world", name: "image.png")
        let vm = SearchViewModel()
        vm.query = "hello"
        vm.search(in: tmpDir)
        try await waitForCompletion(vm)
        #expect(vm.results.isEmpty)
    }

    @Test("Swift files are searched")
    func searchesSwiftFiles() async throws {
        try write("func findMe() {}", name: "code.swift")
        let vm = SearchViewModel()
        vm.query = "findMe"
        vm.search(in: tmpDir)
        try await waitForResults(vm)
        #expect(!vm.results.isEmpty)
    }

    @Test("JSON files are searched")
    func searchesJsonFiles() async throws {
        try write("{\"key\": \"findMe\"}", name: "data.json")
        let vm = SearchViewModel()
        vm.query = "findMe"
        vm.search(in: tmpDir)
        try await waitForResults(vm)
        #expect(!vm.results.isEmpty)
    }

    // MARK: - Result limit

    @Test("Results do not exceed 100 entries")
    func resultsCapAt100() async throws {
        let content = Array(repeating: "match target line", count: 200).joined(separator: "\n")
        try content.write(to: tmpDir.appendingPathComponent("big.md"), atomically: true, encoding: .utf8)
        let vm = SearchViewModel()
        vm.query = "match target"
        vm.search(in: tmpDir)
        try await waitForResults(vm)
        #expect(vm.results.count <= 100)
    }

    // MARK: - No false positives

    @Test("Non-matching query returns empty results")
    func noFalsePositives() async throws {
        try write("completely different content", name: "note.md")
        let vm = SearchViewModel()
        vm.query = "xyznotfound"
        vm.search(in: tmpDir)
        try await waitForCompletion(vm)
        #expect(vm.results.isEmpty)
    }

    // MARK: - isSearching flag

    @Test("isSearching becomes false after completion")
    func isSearchingFalseAfterCompletion() async throws {
        try write("sample content", name: "note.md")
        let vm = SearchViewModel()
        vm.query = "sample"
        vm.search(in: tmpDir)
        try await waitForCompletion(vm)
        #expect(!vm.isSearching)
    }
}
