import Foundation
import Observation

@Observable
final class GitViewModel {
    var isGitRepo: Bool = false
    var branch: String = ""
    var changedFiles: [GitFileStatus] = []
    var recentCommits: [GitCommit] = []
    var selectedFile: GitFileStatus? = nil
    var diffContent: String = ""
    var commitMessage: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var showError: Bool = false

    private var service: GitService?

    // MARK: - Setup

    func configure(repoURL: URL) {
        let svc = GitService(repoURL: repoURL)
        self.service = svc
        // Run isGitRepo check off the main thread to avoid blocking UI
        Task.detached { [weak self] in
            guard let self else { return }
            let isRepo = svc.isGitRepo()
            await MainActor.run { self.isGitRepo = isRepo }
            if isRepo {
                await MainActor.run { self.refresh() }
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard let service else { return }
        isLoading = true
        Task.detached { [weak self] in
            guard let self else { return }
            let branch  = service.currentBranch()
            let files   = service.status()
            let commits = service.recentCommits()
            await MainActor.run {
                self.branch = branch
                self.changedFiles = files
                self.recentCommits = commits
                self.isLoading = false
                // Refresh diff if file still selected
                if let sel = self.selectedFile,
                   let updated = files.first(where: { $0.path == sel.path }) {
                    self.selectedFile = updated
                    self.diffContent = service.diff(for: updated.path, staged: updated.isStaged)
                }
            }
        }
    }

    // MARK: - Diff

    func selectFile(_ file: GitFileStatus) {
        guard let service else { return }
        selectedFile = file
        Task.detached { [weak self] in
            guard let self else { return }
            let diff = service.diff(for: file.path, staged: file.isStaged)
            await MainActor.run { self.diffContent = diff }
        }
    }

    // MARK: - Staging

    func stage(_ file: GitFileStatus) {
        performGitOp { try self.service?.stage(file.path) }
    }

    func unstage(_ file: GitFileStatus) {
        performGitOp { try self.service?.unstage(file.path) }
    }

    func stageAll() {
        performGitOp { try self.service?.stageAll() }
    }

    // MARK: - Commit

    func commit() {
        guard let service else { return }
        let msg = commitMessage
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try service.commit(message: msg)
                await MainActor.run {
                    self.commitMessage = ""
                    self.selectedFile = nil
                    self.diffContent = ""
                    self.refresh()
                }
            } catch {
                await MainActor.run { self.showAppError(error) }
            }
        }
    }

    // MARK: - Private

    private func performGitOp(_ op: @escaping () throws -> Void) {
        guard service != nil else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try op()
                await MainActor.run { self.refresh() }
            } catch {
                await MainActor.run { self.showAppError(error) }
            }
        }
    }

    private func showAppError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
