import Foundation

/// E1 の 1 セッション（Local ディレクトリ、または git worktree）。
struct WorktreeSession: Identifiable, Equatable {
    let id: UUID
    /// 表示名（ディレクトリ名ベース）
    var name: String
    var worktreePath: URL
    /// `git branch --show-current` 相当（worktree のみ）
    var branchName: String?
    /// リポジトリのメイン worktree か
    var isMainWorktree: Bool
    /// ユーザー追加の Local セッション（PTY cwd = worktreePath）
    var isLocalSession: Bool
    var lastAccessedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        worktreePath: URL,
        branchName: String?,
        isMainWorktree: Bool,
        isLocalSession: Bool = false,
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.isMainWorktree = isMainWorktree
        self.isLocalSession = isLocalSession
        self.lastAccessedAt = lastAccessedAt
    }

    static func localDirectory(
        name: String,
        path: URL,
        id: UUID = UUID()
    ) -> WorktreeSession {
        WorktreeSession(
            id: id,
            name: name,
            worktreePath: path.standardizedFileURL,
            branchName: nil,
            isMainWorktree: false,
            isLocalSession: true
        )
    }

    var displayPath: String {
        (worktreePath.path as NSString).abbreviatingWithTildeInPath
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