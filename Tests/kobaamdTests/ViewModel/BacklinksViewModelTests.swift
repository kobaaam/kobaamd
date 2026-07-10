import Testing
@testable import kobaamd
import Foundation

@Suite("BacklinksViewModel")
@MainActor
struct BacklinksViewModelTests {
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    var tmpDir: URL { workspace.root }

    // MARK: - Helpers

    private func makeVM() -> BacklinksViewModel {
        BacklinksViewModel(
            checker: NoOpBacklinkContextChecker(),
            cache: BacklinkContextCache(fileURL: tmpDir.appendingPathComponent("cache.json"))
        )
    }

    private func waitForLoad(_ vm: BacklinksViewModel) async {
        // refresh() の内部に 800ms 遅延があるため余裕をもって 4 秒待つ
        await eventually(timeout: .seconds(4)) { !vm.isLoading && (vm.linked.count > 0 || vm.unlinked.count > 0) }
    }

    private func waitForClear(_ vm: BacklinksViewModel) async {
        await eventually(timeout: .seconds(4)) { !vm.isLoading }
    }

    // MARK: - Initial state

    @Test("Initial state is empty and not loading")
    func initialStateIsEmpty() {
        let vm = makeVM()
        #expect(vm.linked.isEmpty)
        #expect(vm.unlinked.isEmpty)
        #expect(!vm.isLoading)
    }

    // MARK: - Backlink list building

    @Test("Detects wikilink as linked backlink")
    func detectsWikiLinkAsLinked() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        try workspace.write("Reference [[target]] here.", to: "source.md")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        await waitForLoad(vm)

        #expect(!vm.linked.isEmpty)
        #expect(vm.linked.first?.kind == .linked)
        #expect(vm.linked.first?.matchedText == "[[target]]")
    }

    @Test("Detects markdown link as linked backlink")
    func detectsMarkdownLinkAsLinked() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        try workspace.write("[go](target.md)", to: "source.md")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        await waitForLoad(vm)

        #expect(!vm.linked.isEmpty)
        #expect(vm.unlinked.isEmpty)
    }

    @Test("No backlinks when no other files reference target")
    func noBacklinksWhenNoReferences() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        try workspace.write("Completely unrelated content.", to: "other.md")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        // NoOpBacklinkContextChecker が nil を返すため unlinked は空のまま
        await waitForClear(vm)

        #expect(vm.linked.isEmpty)
        #expect(vm.unlinked.isEmpty)
        #expect(!vm.isLoading)
    }

    // MARK: - nil currentURL

    @Test("Nil currentURL clears results")
    func nilCurrentURLClearsResults() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        try workspace.write("Reference [[target]] here.", to: "source.md")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        await waitForLoad(vm)
        #expect(!vm.linked.isEmpty)

        vm.refresh(currentURL: nil, workspaceFolders: [tmpDir])
        // nil 渡し時は 800ms 後に linked/unlinked がクリアされる
        await eventually(timeout: .seconds(4)) { vm.linked.isEmpty && vm.unlinked.isEmpty && !vm.isLoading }
        #expect(vm.linked.isEmpty)
        #expect(vm.unlinked.isEmpty)
        #expect(!vm.isLoading)
    }

    // MARK: - File switch debounce

    @Test("Rapid refresh calls are debounced to last call")
    func rapidRefreshDebounced() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        try workspace.write("Reference [[target]] here.", to: "source.md")
        let other = try workspace.write("# Other", to: "other.md")

        let vm = makeVM()
        // 連続呼び出し。最初の target への refresh は 800ms 以内に cancel される想定。
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        vm.refresh(currentURL: other, workspaceFolders: [tmpDir])

        await waitForClear(vm)
        // other.md には誰も参照していないので linked は空
        #expect(vm.linked.isEmpty)
    }

    // MARK: - Empty workspace

    @Test("Empty folders produces empty results")
    func emptyFoldersProducesEmptyResults() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        let emptyDir = try workspace.makeDir("empty")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [emptyDir])
        await waitForClear(vm)

        #expect(vm.linked.isEmpty)
        #expect(vm.unlinked.isEmpty)
        #expect(!vm.isLoading)
    }

    // MARK: - Self-reference exclusion

    @Test("Self-reference is excluded from results")
    func selfReferenceExcluded() async throws {
        // ターゲットファイル自体が [[target]] を含む場合でも自身はスキャン対象外
        let target = try workspace.write("# Target\n[[target]] is me.", to: "target.md")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        await waitForClear(vm)

        #expect(vm.linked.isEmpty)
    }

    // MARK: - convertToLink

    @Test("convertToLink removes backlink from unlinked list")
    func convertToLinkRemovesFromUnlinked() async throws {
        // NoOpBacklinkContextChecker は判定を nil で返すため unlinked は通常空。
        // 手動で unlinked に Backlink を注入してテストする。
        let sourceFile = try workspace.write("This target is here.", to: "source.md")
        let targetFile = try workspace.write("# Target", to: "target.md")

        let vm = makeVM()
        // BacklinksScanner.scan で unlinked を取得する（NoOp checker なので acceptedUnlinked は空だが
        // scan 自体の unlinked 候補を直接 BacklinksScanner 経由で確認できる）
        let scan = BacklinksScanner.scan(
            sourceURL: sourceFile,
            sourceContent: "This target is here.",
            targetURL: targetFile
        )
        // scan.unlinked に候補があることを確認
        #expect(!scan.unlinked.isEmpty)
        // vm.unlinked に注入
        vm.unlinked = scan.unlinked

        // currentTargetURL は private なので convertToLink が guard を通れるよう
        // refresh を一度呼んで currentTargetURL を設定する
        vm.refresh(currentURL: targetFile, workspaceFolders: [tmpDir])
        // refresh の isLoading が落ち着くのを待つ（800ms delay）
        await waitForClear(vm)

        // unlinked を再注入（refresh で上書きされるため）
        vm.unlinked = scan.unlinked
        let initialCount = vm.unlinked.count

        await vm.convertToLink(vm.unlinked[0])

        #expect(vm.unlinked.count == initialCount - 1)
        // ファイルが [[target]] に書き換えられていることを確認
        let updated = try String(contentsOf: sourceFile, encoding: .utf8)
        #expect(updated.contains("[[target]]"))
    }

    // MARK: - Multiple linked sources

    @Test("Multiple files referencing target are all detected")
    func multipleSourcesDetected() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        try workspace.write("Link [[target]] from A.", to: "a.md")
        try workspace.write("[go](target.md) from B.", to: "b.md")
        try workspace.write("Another [[target|alias]] from C.", to: "c.md")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        await waitForLoad(vm)

        #expect(vm.linked.count == 3)
    }

    // MARK: - Sorted results

    @Test("Linked results are sorted by source path then match location")
    func linkedResultsAreSorted() async throws {
        let target = try workspace.write("# Target", to: "target.md")
        // z.md > a.md のパス順
        try workspace.write("[[target]] later [[target]] again.", to: "z.md")
        try workspace.write("[[target]] early.", to: "a.md")

        let vm = makeVM()
        vm.refresh(currentURL: target, workspaceFolders: [tmpDir])
        await waitForLoad(vm)

        // a.md が先に来るはず
        #expect(vm.linked.count >= 2)
        let firstPath = vm.linked.first?.sourceURL.lastPathComponent
        #expect(firstPath == "a.md")
    }
}
