import AppKit
import Foundation
import Observation

/// E1 の active session とファイルツリー / ターミナル / エディタの同期。
@Observable
@MainActor
final class SessionCoordinator {
    /// git worktree UI は当面非表示（WorktreeService は将来用に残す）。
    static let gitWorktreeEnabled = false

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

    var terminalSessions: [WorktreeSession] { sessions }

    var activeTerminalSession: WorktreeSession {
        activeSession ?? sessions[0]
    }

    var canRemoveSessions: Bool { sessions.count > 1 }

    func attach(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    func bootstrapIfNeeded() {
        loadPersistedLocalSessions()
        if sessions.isEmpty {
            appendDefaultHomeSession()
        }
        if let id = activeSessionID, sessions.contains(where: { $0.id == id }) {
            selectSession(id: id, skipRefresh: true)
        } else {
            selectSession(id: sessions[0].id, skipRefresh: true)
        }
    }

    /// フォルダを選んで Local セッションを追加する。
    @discardableResult
    func addLocalSession() -> Bool {
        guard let url = pickDirectory(prompt: "セッションの作業フォルダ") else { return false }
        insertLocalSession(at: url)
        return true
    }

    func removeLocalSession(id: UUID) {
        guard canRemoveSessions else { return }
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            selectSession(id: sessions[0].id)
        } else {
            persistLocalSessions()
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
        AppState.saveLastFolder(session.worktreePath)
        persistLocalSessions()

        if !skipRefresh {
            PerfLogger.event("SessionCoordinator.selectSession", "path=\(session.worktreePath.lastPathComponent)")
        }
    }

    // MARK: - git worktree（非表示・将来用）

    func refreshSessions(anchorDirectory: URL) async {
        guard Self.gitWorktreeEnabled else { return }
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

    func handleFolderOpened(_ url: URL) async {
        if Self.gitWorktreeEnabled {
            await refreshSessions(anchorDirectory: url)
        } else {
            insertLocalSession(at: url)
        }
    }

    // MARK: - Private

    private func loadPersistedLocalSessions() {
        let (loaded, activeID) = AppState.loadE1LocalSessions()
        sessions = loaded
        activeSessionID = activeID
        loadError = nil
    }

    private func persistLocalSessions() {
        AppState.saveE1LocalSessions(sessions, activeID: activeSessionID)
    }

    private func appendDefaultHomeSession() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let session = WorktreeSession.localDirectory(name: "Home", path: home)
        sessions = [session]
        activeSessionID = session.id
        persistLocalSessions()
    }

    private func insertLocalSession(at url: URL) {
        let standardized = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        if let existing = sessions.first(where: { $0.worktreePath == standardized }) {
            selectSession(id: existing.id)
            return
        }
        let name = uniqueLocalName(for: standardized)
        let session = WorktreeSession.localDirectory(name: name, path: standardized)
        sessions.append(session)
        persistLocalSessions()
        selectSession(id: session.id)
    }

    private func uniqueLocalName(for url: URL) -> String {
        let base = url.lastPathComponent.isEmpty ? "Session" : url.lastPathComponent
        var candidate = base
        var counter = 2
        while sessions.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    private func pickDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}