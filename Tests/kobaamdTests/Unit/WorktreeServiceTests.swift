import Testing
@testable import kobaamd
import Foundation

@Suite("WorktreeService")
struct WorktreeServiceTests {
    private let fixture = """
        worktree /repo/main
        HEAD aaa1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /repo/feature/foo
        HEAD bbb2222222222222222222222222222222222222222
        branch refs/heads/feature/foo

        worktree /repo/detached-wt
        HEAD ccc3333333333333333333333333333333333333333
        detached

        worktree /repo/gone
        HEAD ddd4444444444444444444444444444444444444444
        branch refs/heads/old
        prunable gitdir file points to non-existent location
        """

    @Test("porcelain fixture parses three logical worktrees")
    func parsePorcelainFixture() {
        let records = WorktreeService.parsePorcelain(fixture)
        #expect(records.count == 4)

        #expect(records[0].path.path == "/repo/main")
        #expect(records[0].branchName == "main")
        #expect(records[0].isDetached == false)

        #expect(records[1].path.path == "/repo/feature/foo")
        #expect(records[1].branchName == "feature/foo")

        #expect(records[2].isDetached == true)
        #expect(records[2].branchName == nil)

        #expect(records[3].isPrunable == true)
    }

    @Test("makeSessions marks main worktree and sorts main first")
    func makeSessionsMainFirst() {
        let records = WorktreeService.parsePorcelain(fixture)
        let root = URL(fileURLWithPath: "/repo/main", isDirectory: true)
        let sessions = WorktreeService().makeSessions(records: records, repositoryRoot: root)
        #expect(sessions.first?.isMainWorktree == true)
        #expect(sessions.first?.worktreePath.path == "/repo/main")
        #expect(sessions.contains { $0.branchName == "feature/foo" })
    }

    @Test("prunable flag is set on porcelain records")
    func prunableRecordsIdentified() {
        let records = WorktreeService.parsePorcelain(fixture)
        #expect(records.contains(where: { $0.isPrunable }))
        #expect(records.filter { !$0.isPrunable }.count == 3)
    }
}