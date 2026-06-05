import Testing
@testable import kobaamd
import Foundation

@Suite("SessionCoordinator")
struct SessionCoordinatorTests {
    @Test("selectSession scopes file tree and clears editor tabs")
    @MainActor
    func selectSessionScopesWorktreeAndResetsEditor() {
        let vm = AppViewModel()
        let coordinator = SessionCoordinator()
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

    @Test("addLocalSession deduplicates same directory")
    @MainActor
    func addLocalSessionDeduplicates() async {
        let vm = AppViewModel()
        let coordinator = SessionCoordinator()
        coordinator.attach(appViewModel: vm)
        let path = FileManager.default.temporaryDirectory
        coordinator.sessions = [WorktreeSession.localDirectory(name: "tmp", path: path)]
        coordinator.activeSessionID = coordinator.sessions[0].id

        await coordinator.handleFolderOpened(path)
        #expect(coordinator.sessions.count == 1)
        #expect(coordinator.activeSessionID == coordinator.sessions[0].id)
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