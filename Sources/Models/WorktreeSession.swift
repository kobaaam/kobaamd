import Foundation

/// E1 の 1 セッション = 1 つの git worktree（PRD KMD-218 §4）。
struct WorktreeSession: Identifiable, Equatable {
    let id: UUID
    /// 表示名（worktree ディレクトリ名）
    var name: String
    var worktreePath: URL
    /// `git branch --show-current` 相当（porcelain の `branch refs/heads/...` から抽出）
    var branchName: String?
    /// リポジトリのメイン worktree か
    var isMainWorktree: Bool
    var lastAccessedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        worktreePath: URL,
        branchName: String?,
        isMainWorktree: Bool,
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.isMainWorktree = isMainWorktree
        self.lastAccessedAt = lastAccessedAt
    }

    /// git 未接続時のフォールバック（PTY の cwd = ホーム）。
    static let localShellID = UUID(uuidString: "E1A10000-0000-4000-8000-000000000001")!

    static func localShell(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> WorktreeSession {
        WorktreeSession(
            id: localShellID,
            name: "Local",
            worktreePath: home,
            branchName: nil,
            isMainWorktree: false
        )
    }
}

/// `git worktree list --porcelain` の 1 ブロック。
struct WorktreeRecord: Equatable {
    var path: URL
    var head: String?
    var branchName: String?
    var isBare: Bool
    var isDetached: Bool
    var isPrunable: Bool
}