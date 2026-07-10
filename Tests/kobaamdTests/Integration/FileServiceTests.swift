import Testing
@testable import kobaamd
import Foundation

@Suite("FileService", .serialized)
struct FileServiceTests {
    let svc = FileService()
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    var tmpDir: URL { workspace.root }

    // MARK: - supportedExtensions

    @Test("Common extensions are supported")
    func supportedExtensionsContainsCoreTypes() {
        for ext in ["md", "markdown", "txt", "swift", "json", "yaml", "py", "sh"] {
            #expect(FileService.supportedExtensions.contains(ext), "\(ext) should be supported")
        }
    }

    @Test("Unknown extensions are excluded")
    func supportedExtensionsExcludesUnknown() {
        for ext in ["docx", "pdf", "xlsx", "exe", "png", "jpg", "xyz"] {
            #expect(!FileService.supportedExtensions.contains(ext), "\(ext) should not be supported")
        }
    }

    // MARK: - readFile / saveFile

    @Test("Read returns saved content")
    func readFileReturnsCorrectContent() throws {
        let url = tmpDir.appendingPathComponent("test.md")
        let expected = "# Hello\nContent here."
        try svc.saveFile(at: url, content: expected)
        #expect(try svc.readFile(at: url) == expected)
    }

    @Test("Save and read round trip")
    func saveFileRoundTrip() throws {
        let url = tmpDir.appendingPathComponent("round.txt")
        let content = "line1\nline2\nline3"
        try svc.saveFile(at: url, content: content)
        #expect(try svc.readFile(at: url) == content)
    }

    @Test("Read missing file throws")
    func readFileMissingThrows() {
        let url = tmpDir.appendingPathComponent("nonexistent.md")
        #expect(throws: (any Error).self) { try svc.readFile(at: url) }
    }

    @Test("Save overwrites existing content")
    func saveFileOverwrites() throws {
        let url = tmpDir.appendingPathComponent("overwrite.md")
        try svc.saveFile(at: url, content: "original")
        try svc.saveFile(at: url, content: "updated")
        #expect(try svc.readFile(at: url) == "updated")
    }

    // MARK: - loadNodes

    @Test("Unsupported extensions are filtered out")
    func loadNodesFiltersUnsupportedExtensions() throws {
        try "".write(to: tmpDir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("b.docx"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("c.pdf"), atomically: true, encoding: .utf8)
        let names = svc.loadNodes(at: tmpDir).map { $0.name }
        #expect(names.contains("a.md"))
        #expect(!names.contains("b.docx"))
        #expect(!names.contains("c.pdf"))
    }

    @Test("Directories sort before files")
    func loadNodesSortsDirectoriesFirst() throws {
        let dir = tmpDir.appendingPathComponent("sort-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zzz = dir.appendingPathComponent("zzz", isDirectory: true)
        try FileManager.default.createDirectory(at: zzz, withIntermediateDirectories: false)
        try "".write(to: zzz.appendingPathComponent("inside.md"), atomically: true, encoding: .utf8)
        try "".write(to: dir.appendingPathComponent("aaa.md"), atomically: true, encoding: .utf8)
        let nodes = svc.loadNodes(at: dir)
        #expect(nodes.first?.isDirectory == true)
        #expect(nodes.first?.name == "zzz")
    }

    @Test("loadNodes on a file returns empty")
    func loadNodesOnFileReturnsEmpty() throws {
        let file = tmpDir.appendingPathComponent("file.md")
        try "".write(to: file, atomically: true, encoding: .utf8)
        #expect(svc.loadNodes(at: file).isEmpty)
    }

    @Test("Empty directory returns empty nodes")
    func loadNodesEmptyDirectory() {
        #expect(svc.loadNodes(at: tmpDir).isEmpty)
    }

    @Test("Hidden off skips dot directories")
    func loadNodesHidesScratchWhenHiddenOff() throws {
        let scratch = tmpDir.appendingPathComponent(".scratch/member-create", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try "# PRD".write(
            to: scratch.appendingPathComponent("PRD.md"),
            atomically: true,
            encoding: .utf8
        )

        let names = svc.loadNodes(at: tmpDir, showHiddenFiles: false).map(\.name)
        #expect(!names.contains(".scratch"))
    }

    @Test("Hidden on shows scratch and empty dot directories like .git when deps included")
    func loadNodesShowsDotDirectoriesWhenHiddenOn() throws {
        let scratch = tmpDir.appendingPathComponent(".scratch/member-create", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try "# PRD".write(
            to: scratch.appendingPathComponent("PRD.md"),
            atomically: true,
            encoding: .utf8
        )
        let gitDir = tmpDir.appendingPathComponent(".git/objects", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "obj".write(to: gitDir.appendingPathComponent("dummy"), atomically: true, encoding: .utf8)

        let nodes = svc.loadNodes(
            at: tmpDir,
            showHiddenFiles: true,
            includeDependencyDirectories: true
        )
        let names = nodes.map(\.name)
        #expect(names.contains(".scratch"))
        #expect(names.contains(".git"))

        let scratchNode = nodes.first { $0.name == ".scratch" }
        let prd = scratchNode?.children?.first { $0.name == "member-create" }?
            .children?.first { $0.name == "PRD.md" }
        #expect(prd != nil)
    }

    @Test("Dependency directories are skipped by default")
    func loadNodesSkipsDependencyDirectoriesByDefault() throws {
        let nodeModules = tmpDir.appendingPathComponent("node_modules/pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try "dep".write(
            to: nodeModules.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )
        try "# App".write(to: tmpDir.appendingPathComponent("app.md"), atomically: true, encoding: .utf8)

        let names = svc.loadNodes(at: tmpDir, includeDependencyDirectories: false).map(\.name)
        #expect(names.contains("app.md"))
        #expect(!names.contains("node_modules"))
    }

    @Test("Workspace internal .kobaamd directory is always skipped")
    func loadNodesSkipsKobaamdInternalDirectory() throws {
        let internalDir = tmpDir.appendingPathComponent(".kobaamd", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        try "noise".write(to: internalDir.appendingPathComponent("transcript.log"), atomically: true, encoding: .utf8)
        try "# App".write(to: tmpDir.appendingPathComponent("app.md"), atomically: true, encoding: .utf8)

        let names = svc.loadNodes(at: tmpDir, includeDependencyDirectories: true).map(\.name)
        #expect(names.contains("app.md"))
        #expect(!names.contains(".kobaamd"))
    }

    @Test("Dependency directories appear when opt-in enabled")
    func loadNodesIncludesDependencyDirectoriesWhenOptIn() throws {
        let nodeModules = tmpDir.appendingPathComponent("node_modules/pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try "dep".write(
            to: nodeModules.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )

        let names = svc.loadNodes(at: tmpDir, includeDependencyDirectories: true).map(\.name)
        #expect(names.contains("node_modules"))
    }

    // MARK: - createNewFile

    @Test("Missing extension gets .md added")
    func createNewFileAddsMdExtension() throws {
        let url = try svc.createNewFile(in: tmpDir, named: "untitled")
        #expect(url.pathExtension == "md")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Explicit extension is preserved")
    func createNewFilePreservesExtension() throws {
        let url = try svc.createNewFile(in: tmpDir, named: "config.json")
        #expect(url.pathExtension == "json")
    }

    @Test("New file starts empty")
    func createNewFileIsEmpty() throws {
        let url = try svc.createNewFile(in: tmpDir, named: "empty.md")
        #expect(try svc.readFile(at: url) == "")
    }

    // MARK: - DocumentTemplate + loadTemplates

    @Test("DocumentTemplate.parse extracts frontmatter title and description")
    func documentTemplateParseFrontmatter() {
        let content = """
        ---
        title: 技術仕様書
        description: 技術設計書テンプレート
        ---
        # 本文
        """
        let tmpl = DocumentTemplate.parse(filename: "tech-spec", content: content, isBuiltIn: true)
        #expect(tmpl.title == "技術仕様書")
        #expect(tmpl.description == "技術設計書テンプレート")
        #expect(tmpl.content == content)
        #expect(tmpl.isBuiltIn == true)
        #expect(tmpl.id == "tech-spec")
    }

    @Test("DocumentTemplate.parse falls back to filename when no frontmatter")
    func documentTemplateParseNoFrontmatter() {
        let content = "# Just a heading\nSome content."
        let tmpl = DocumentTemplate.parse(filename: "my-template", content: content, isBuiltIn: false)
        #expect(tmpl.title == "my-template")
        #expect(tmpl.description == "")
        #expect(tmpl.isBuiltIn == false)
    }

    @Test("DocumentTemplate.parse handles partial frontmatter (title only)")
    func documentTemplateParsePartialFrontmatter() {
        let content = """
        ---
        title: 議事録
        ---
        # 議事録
        """
        let tmpl = DocumentTemplate.parse(filename: "meeting", content: content, isBuiltIn: true)
        #expect(tmpl.title == "議事録")
        #expect(tmpl.description == "")
    }

    @Test("loadTemplates returns templates from directory with .md files")
    func loadTemplatesFromCustomDirectory() throws {
        // tmpDir に .md ファイルを2つ作成して DocumentTemplate.parse を検証
        let t1Content = """
        ---
        title: My README
        description: A test template
        ---
        # Hello
        """
        let t1 = tmpDir.appendingPathComponent("readme.md")
        try t1Content.write(to: t1, atomically: true, encoding: .utf8)

        let readBack = try String(contentsOf: t1, encoding: .utf8)
        let tmpl = DocumentTemplate.parse(filename: "readme", content: readBack, isBuiltIn: true)
        #expect(tmpl.title == "My README")
        #expect(tmpl.description == "A test template")
        #expect(tmpl.isBuiltIn == true)
        #expect(tmpl.id == "readme")
    }

    @Test("loadTemplates non-.md file yields filename as title")
    func loadTemplatesNonMdFile() {
        let tmpl = DocumentTemplate.parse(filename: "file", content: "data", isBuiltIn: false)
        #expect(tmpl.title == "file")
        #expect(tmpl.description == "")
        #expect(tmpl.isBuiltIn == false)
    }

    @Test("ensureCustomTemplateDirectory creates directory when missing")
    func ensureCustomTemplateDirectoryCreatesDir() throws {
        let testDir = tmpDir.appendingPathComponent("templates_test", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: testDir.path))
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true, attributes: nil)
        #expect(FileManager.default.fileExists(atPath: testDir.path))
    }
}
