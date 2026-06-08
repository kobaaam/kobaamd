import AppKit
import Foundation
import SwiftTerm

/// セッションごとの PTY インスタンス管理（KMD-225, KMD-226）。
@MainActor
final class E1TerminalSessionController {
    static let maxActiveTerminals = 8

    private var terminals: [UUID: E1LocalTerminalView] = [:]
    private var accessOrder: [UUID] = []
    private var startedSessions: Set<UUID> = []

    func terminalView(for session: WorktreeSession) -> E1LocalTerminalView {
        if let existing = terminals[session.id] {
            touch(session.id)
            return existing
        }
        evictIfNeeded()
        let view = E1LocalTerminalView(frame: .zero)
        view.configureAppearance()
        view.pasteImageDirectory = session.worktreePath
            .appendingPathComponent(".kobaamd/pastes", isDirectory: true)
        terminals[session.id] = view
        touch(session.id)
        return view
    }

    func ensureProcessStarted(for session: WorktreeSession) {
        let view = terminalView(for: session)
        guard !startedSessions.contains(session.id) else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-kitty", trueColor: true)
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            environment.append("PATH=\(path)")
        }
        view.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment,
            currentDirectory: session.worktreePath.path
        )
        view.enableClaudeCodeKeyboard()
        startedSessions.insert(session.id)
    }

    func suspendSession(id: UUID) {
        guard let view = terminals[id] else { return }
        if view.process.running {
            view.terminate()
        }
        startedSessions.remove(id)
    }

    private func evictIfNeeded() {
        while terminals.count >= Self.maxActiveTerminals, let oldest = accessOrder.first {
            suspendSession(id: oldest)
            terminals.removeValue(forKey: oldest)
            accessOrder.removeAll { $0 == oldest }
        }
    }

    private func touch(_ id: UUID) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }
}

private extension E1LocalTerminalView {
    func configureAppearance(theme: ColorTheme = AppState.shared.selectedTheme) {
        nativeForegroundColor = theme.editorText
        nativeBackgroundColor = theme.editorBackground
    }
}