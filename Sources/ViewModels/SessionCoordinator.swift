import Foundation
import Observation

/// E1 の active session と worktree / ファイルツリー / エディタ状態の同期（KMD-224）。
@Observable
@MainActor
final class SessionCoordinator {
    var sessions: [WorktreeSession] = []
    var activeSessionID: UUID?
    var repositoryRoot: URL?
    var loadError: String?
    var isLoading: Bool = false

    private let worktreeService = WorktreeService()
    private weak var appViewModel: AppViewModel?

    var activeSession: WorktreeSession? {
        guard let id = activeSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// PTY 用セッション一覧。git worktree が無いときは Local のみ。
    var terminalSessions: [WorktreeSession] {
        sessions.isEmpty ? [WorktreeSession.localShell()] : sessions
    }

    /// 中央ターミナルが起動するセッション（worktree 未選択時は Local）。
    var activeTerminalSession: WorktreeSession {
        activeSession ?? WorktreeSession.localShell()
    }

    func attach(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    /// 指定ディレクトリを含む git リポジトリから worktree 一覧を再取得する。
    func refreshSessions(anchorDirectory: URL) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let previousPath = activeSession?.worktreePath

        do {
            let root = try worktreeService.repositoryRoot(containing: anchorDirectory)
            repositoryRoot = root
            let records = try worktreeService.listWorktrees(repositoryRoot: root)
            let built = worktreeService.makeSessions(records: records, repositoryRoot: root)
            sessions = built

            if sessions.isEmpty {
                activeSessionID = nil
                appViewModel?.fileTreeViewModel.clearWorkspace()
                return
            }

            if let previousPath,
               let match = sessions.first(where: { $0.worktreePath == previousPath }) {
                selectSession(id: match.id, skipRefresh: true)
            } else if let main = sessions.first(where: { $0.isMainWorktree }) {
                selectSession(id: main.id, skipRefresh: true)
            } else {
                selectSession(id: sessions[0].id, skipRefresh: true)
            }
        } catch WorktreeServiceError.notAGitRepository {
            sessions = []
            activeSessionID = nil
            loadError = "git リポジトリではありません。フォルダを選び直してください。"
            appViewModel?.fileTreeViewModel.clearWorkspace()
        } catch {
            sessions = []
            activeSessionID = nil
            loadError = error.localizedDescription
            appViewModel?.fileTreeViewModel.clearWorkspace()
        }
    }

    func selectSession(id: UUID, skipRefresh: Bool = false) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        guard activeSessionID != id else { return }

        activeSessionID = id
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].lastAccessedAt = Date()
        }

        guard let vm = appViewModel else { return }

        vm.resetEditorStateForSessionSwitch()
        vm.fileTreeViewModel.setScopedWorktree(session.worktreePath)
        vm.refreshQuickOpenIndex()

        if !skipRefresh {
            PerfLogger.event("SessionCoordinator.selectSession", "path=\(session.worktreePath.lastPathComponent)")
        }
    }

    /// 起動時: 保存済みワークスペースまたは pending フォルダから bootstrap。
    func bootstrapIfNeeded() async {
        guard let vm = appViewModel else { return }
        if let folder = vm.fileTreeViewModel.folders.first?.url {
            await refreshSessions(anchorDirectory: folder)
            return
        }
        if let last = AppState.shared.loadLastFolder() {
            await refreshSessions(anchorDirectory: last)
            return
        }
        activateLocalShell()
    }

    /// git 未接続でもターミナルとファイルツリーをホームで使えるようにする。
    func activateLocalShell() {
        activeSessionID = nil
        guard let vm = appViewModel else { return }
        let home = WorktreeSession.localShell()
        vm.fileTreeViewModel.setScopedWorktree(home.worktreePath)
        vm.refreshQuickOpenIndex()
    }

    func handleFolderOpened(_ url: URL) async {
        await refreshSessions(anchorDirectory: url)
    }
}