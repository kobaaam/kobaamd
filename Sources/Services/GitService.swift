import Foundation

// MARK: - Data models

struct GitFileStatus: Identifiable {
    enum State: String {
        case modified  = "M"
        case added     = "A"
        case deleted   = "D"
        case renamed   = "R"
        case untracked = "?"
        case staged    = "S"

        var label: String {
            switch self {
            case .modified:  return "変更"
            case .added:     return "追加"
            case .deleted:   return "削除"
            case .renamed:   return "名前変更"
            case .untracked: return "未追跡"
            case .staged:    return "ステージ済"
            }
        }
    }

    let id = UUID()
    var path: String
    var state: State
    var isStaged: Bool
}

struct GitCommit: Identifiable {
    let id = UUID()
    var hash: String
    var shortHash: String
    var subject: String
    var author: String
    var date: String
}

// MARK: - Service

final class GitService {

    private let repoURL: URL

    init(repoURL: URL) {
        self.repoURL = repoURL
    }

    // MARK: - Repository info

    func isGitRepo() -> Bool {
        let result = run(["rev-parse", "--is-inside-work-tree"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    func currentBranch() -> String {
        let result = run(["rev-parse", "--abbrev-ref", "HEAD"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func repoRoot() -> URL? {
        let result = run(["rev-parse", "--show-toplevel"])
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Status

    func status() -> [GitFileStatus] {
        let result = run(["status", "--porcelain", "-u"])
        guard result.exitCode == 0 else { return [] }
        return result.output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { parseStatusLine($0) }
    }

    private func parseStatusLine(_ line: String) -> GitFileStatus? {
        guard line.count >= 3 else { return nil }
        let x = String(line.prefix(1))   // index (staged)
        let y = String(line.dropFirst(1).prefix(1))  // worktree (unstaged)
        let path = String(line.dropFirst(3))

        // Staged changes
        if x != " " && x != "?" {
            let state: GitFileStatus.State
            switch x {
            case "M": state = .staged
            case "A": state = .added
            case "D": state = .deleted
            case "R": state = .renamed
            default:  state = .modified
            }
            return GitFileStatus(path: path, state: state, isStaged: true)
        }
        // Unstaged changes
        if y == "M" { return GitFileStatus(path: path, state: .modified, isStaged: false) }
        if y == "D" { return GitFileStatus(path: path, state: .deleted,  isStaged: false) }
        if x == "?" { return GitFileStatus(path: path, state: .untracked, isStaged: false) }
        return nil
    }

    // MARK: - Diff

    /// Returns unified diff for a file (unstaged changes vs index, or index vs HEAD if staged)
    func diff(for path: String, staged: Bool = false) -> String {
        var args = ["diff", "--unified=3"]
        if staged { args.append("--cached") }
        args.append("--")
        args.append(path)
        let result = run(args)
        return result.output.isEmpty ? "（差分なし）" : result.output
    }

    /// Returns diff of a file vs HEAD (useful for showing all changes)
    func diffVsHead(for path: String) -> String {
        let result = run(["diff", "HEAD", "--unified=3", "--", path])
        return result.output.isEmpty ? "（差分なし）" : result.output
    }

    // MARK: - Staging

    func stage(_ path: String) throws {
        let result = run(["add", "--", path])
        if result.exitCode != 0 {
            throw GitError.commandFailed(result.error)
        }
    }

    func unstage(_ path: String) throws {
        let result = run(["restore", "--staged", "--", path])
        if result.exitCode != 0 {
            throw GitError.commandFailed(result.error)
        }
    }

    func stageAll() throws {
        let result = run(["add", "-A"])
        if result.exitCode != 0 {
            throw GitError.commandFailed(result.error)
        }
    }

    // MARK: - Commit

    func commit(message: String) throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.emptyCommitMessage
        }
        let result = run(["commit", "-m", message])
        if result.exitCode != 0 {
            throw GitError.commandFailed(result.error)
        }
    }

    // MARK: - Log

    func recentCommits(count: Int = 20) -> [GitCommit] {
        let fmt = "%H\t%h\t%s\t%an\t%ar"
        let result = run(["log", "--format=\(fmt)", "-n", "\(count)"])
        guard result.exitCode == 0 else { return [] }
        return result.output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 5 else { return nil }
                return GitCommit(hash: parts[0], shortHash: parts[1],
                                 subject: parts[2], author: parts[3], date: parts[4])
            }
    }

    // MARK: - Shell runner

    private struct RunResult {
        let output: String
        let error:  String
        let exitCode: Int32
    }

    private func run(_ args: [String]) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = repoURL

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return RunResult(output: "", error: error.localizedDescription, exitCode: -1)
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(output: out, error: err, exitCode: process.terminationStatus)
    }
}

// MARK: - Errors

enum GitError: LocalizedError {
    case commandFailed(String)
    case emptyCommitMessage

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "Gitコマンドエラー: \(msg)"
        case .emptyCommitMessage:    return "コミットメッセージを入力してください"
        }
    }
}
