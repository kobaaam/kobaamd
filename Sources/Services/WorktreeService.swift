import Foundation

enum WorktreeServiceError: Error, Equatable {
    case gitFailed(exitCode: Int32, stderr: String)
    case notAGitRepository
    case parseFailed
}

/// git worktree 一覧の取得と porcelain パース（KMD-221）。
struct WorktreeService {
    private let fileManager: FileManager
    private let gitExecutable: URL
    private let runGit: @Sendable ([String], URL) throws -> String

    init(
        fileManager: FileManager = .default,
        gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git"),
        runGit: (@Sendable ([String], URL) throws -> String)? = nil
    ) {
        self.fileManager = fileManager
        self.gitExecutable = gitExecutable
        self.runGit = runGit ?? WorktreeService.defaultRunGit(executable: gitExecutable)
    }

    /// `directory` を含むリポジトリのルートを返す。
    func repositoryRoot(containing directory: URL) throws -> URL {
        let trimmed = try runGit(["rev-parse", "--show-toplevel"], directory)
        let path = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw WorktreeServiceError.notAGitRepository }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// リポジトリ内の worktree 一覧（prunable / 存在しないパスは除外）。
    func listWorktrees(repositoryRoot: URL) throws -> [WorktreeRecord] {
        let output = try runGit(["worktree", "list", "--porcelain"], repositoryRoot)
        let records = Self.parsePorcelain(output)
        return records.filter { record in
            !record.isPrunable && fileManager.fileExists(atPath: record.path.path)
        }
    }

    func makeSessions(records: [WorktreeRecord], repositoryRoot: URL) -> [WorktreeSession] {
        let rootPath = repositoryRoot.standardizedFileURL.path
        return records.map { record in
            let path = record.path.standardizedFileURL
            let isMain = path.path == rootPath
            return WorktreeSession(
                name: path.lastPathComponent,
                worktreePath: path,
                branchName: record.branchName,
                isMainWorktree: isMain,
                lastAccessedAt: Date()
            )
        }
        .sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree { return lhs.isMainWorktree }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Porcelain parser

    static func parsePorcelain(_ output: String) -> [WorktreeRecord] {
        var records: [WorktreeRecord] = []
        var path: URL?
        var head: String?
        var branchName: String?
        var isBare = false
        var isDetached = false
        var isPrunable = false

        func flush() {
            guard let currentPath = path else { return }
            records.append(
                WorktreeRecord(
                    path: currentPath,
                    head: head,
                    branchName: branchName,
                    isBare: isBare,
                    isDetached: isDetached,
                    isPrunable: isPrunable
                )
            )
            path = nil
            head = nil
            branchName = nil
            isBare = false
            isDetached = false
            isPrunable = false
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                flush()
                let p = String(line.dropFirst("worktree ".count))
                path = URL(fileURLWithPath: p, isDirectory: true)
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branchName = shortBranchName(from: ref)
            } else if line == "bare" {
                isBare = true
            } else if line == "detached" {
                isDetached = true
            } else if line.hasPrefix("prunable ") {
                isPrunable = true
            }
        }
        flush()
        return records
    }

    static func shortBranchName(from ref: String) -> String? {
        let prefix = "refs/heads/"
        if ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return ref.isEmpty ? nil : ref
    }

    // MARK: - Git process

    private static func defaultRunGit(executable: URL) -> @Sendable ([String], URL) throws -> String {
        { arguments, directory in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw WorktreeServiceError.gitFailed(
                    exitCode: process.terminationStatus,
                    stderr: err.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return out
        }
    }
}