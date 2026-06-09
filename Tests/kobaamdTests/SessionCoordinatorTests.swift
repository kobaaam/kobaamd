import Testing
@testable import kobaamd
import Foundation

@Suite("SessionCoordinator", .serialized)
struct SessionCoordinatorTests {
    @MainActor
    private func makeCoordinator() -> SessionCoordinator {
        AppState.saveE1LocalSessions([], activeID: nil)
        return SessionCoordinator()
    }

    @Test("bootstrap applies file tree even when session already active")
    @MainActor
    func bootstrapScopesFileTreeOnFirstLoad() {
        let vm = AppViewModel()
        let coordinator = makeCoordinator()
        let path = FileManager.default.homeDirectoryForCurrentUser
        let session = WorktreeSession.localDirectory(name: "Home", path: path)
        coordinator.sessions = [session]
        coordinator.activeSessionID = session.id
        coordinator.attach(appViewModel: vm)

        coordinator.bootstrapIfNeeded()

        #expect(vm.fileTreeViewModel.rootURL == path.standardizedFileURL)
        #expect(!vm.fileTreeViewModel.folders.isEmpty)
    }

    @Test("selectSession scopes file tree and clears editor tabs")
    @MainActor
    func selectSessionScopesWorktreeAndResetsEditor() {
        let vm = AppViewModel()
        let coordinator = makeCoordinator()
        coordinator.attach(appViewModel: vm)

        let mainPath = URL(fileURLWithPath: "/tmp/repo-main", isDirectory: true)
        let featurePath = URL(fileURLWithPath: "/tmp/repo-feature", isDirectory: true)
        let main = WorktreeSession.localDirectory(name: "main", path: mainPath)
        let feature = WorktreeSession.localDirectory(name: "feature", path: featurePath)
        coordinator.sessions = [main, feature]
        coordinator.activeSessionID = main.id
        coordinator.selectSession(id: main.id, skipRefresh: true)
        vm.openInTab(url: mainPath.appendingPathComponent("a.md"), content: "# A")

        coordinator.selectSession(id: feature.id)

        #expect(coordinator.activeSessionID == feature.id)
        #expect(vm.fileTreeViewModel.rootURL == featurePath)
        #expect(vm.tabs.isEmpty)
        #expect(vm.selectedFileURL == nil)
    }

    @Test("same directory can spawn multiple sessions")
    @MainActor
    func sameDirectoryAllowsMultipleSessions() async throws {
        let vm = AppViewModel()
        let coordinator = makeCoordinator()
        coordinator.attach(appViewModel: vm)
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-multi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        coordinator.sessions = [WorktreeSession.localDirectory(name: path.lastPathComponent, path: path)]
        coordinator.activeSessionID = coordinator.sessions[0].id

        await coordinator.handleFolderOpened(path)

        #expect(coordinator.sessions.count == 2)
        #expect(Set(coordinator.sessions.map(\.worktreePath)) == [path.standardizedFileURL])
        #expect(Set(coordinator.sessions.map(\.id)).count == 2)
        #expect(coordinator.sessions[1].name == "\(path.lastPathComponent) 2")
    }

    @Test("duplicateSession clones active directory")
    @MainActor
    func duplicateSessionCreatesSibling() throws {
        let vm = AppViewModel()
        let coordinator = makeCoordinator()
        coordinator.attach(appViewModel: vm)
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-session-dup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let original = WorktreeSession.localDirectory(name: "project", path: path)
        coordinator.sessions = [original]
        coordinator.activeSessionID = original.id
        coordinator.attach(appViewModel: vm)

        coordinator.duplicateSession(id: original.id)

        #expect(coordinator.sessions.count == 2)
        #expect(coordinator.sessions[1].worktreePath == path.standardizedFileURL)
        #expect(coordinator.sessions[1].name == path.lastPathComponent)
        #expect(coordinator.activeSessionID == coordinator.sessions[1].id)
    }

    @Test("E2E fixture builds alpha/beta sessions and scopes Quick Open")
    @MainActor
    func e2eFixtureScopesQuickOpen() async throws {
        let vm = AppViewModel()
        let coordinator = makeCoordinator()
        coordinator.attach(appViewModel: vm)
        coordinator.applyE2ESessionFixture()

        #expect(coordinator.sessions.count == 2)
        #expect(vm.fileTreeViewModel.rootURL?.lastPathComponent == "alpha")
        vm.quickOpenViewModel.filter()
        #expect(vm.quickOpenViewModel.candidates.allSatisfy { vm.quickOpenViewModel.isWithinScope($0.url) })

        guard let betaID = coordinator.sessions.first(where: { $0.name == "beta" })?.id else {
            Issue.record("beta session missing")
            return
        }
        coordinator.selectSession(id: betaID)
        #expect(vm.fileTreeViewModel.rootURL?.lastPathComponent == "beta")
        try await Task.sleep(for: .milliseconds(200))
        vm.refreshQuickOpenIndex()
        vm.quickOpenViewModel.filter()
        let names = Set(vm.quickOpenViewModel.candidates.map(\.fileName))
        #expect(names.contains("beta.md"))
        #expect(!names.contains("alpha.md"))
    }

    @Test("two-worktree fixture sessions remain distinct paths")
    func twoWorktreePathsDistinct() {
        let records = WorktreeService.parsePorcelain("""
            worktree /repo/main
            HEAD aaa1111111111111111111111111111111111111111
            branch refs/heads/main

            worktree /repo/feature
            HEAD bbb2222222222222222222222222222222222222222
            branch refs/heads/feature/foo
            """)
        let root = URL(fileURLWithPath: "/repo/main", isDirectory: true)
        let sessions = WorktreeService().makeSessions(records: records, repositoryRoot: root)
        #expect(sessions.count == 2)
        #expect(Set(sessions.map(\.worktreePath.path)) == ["/repo/main", "/repo/feature"])
    }
}