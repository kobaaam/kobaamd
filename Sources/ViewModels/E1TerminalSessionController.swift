import AppKit
import Foundation
import GhosttyTerminal

/// セッションごとの PTY インスタンス管理（KMD-225, KMD-226）。
@MainActor
final class E1TerminalSessionController {
    static let maxActiveTerminals = E1TerminalMemoryPolicy.maxActiveTerminals

    private var terminals: [UUID: E1LocalTerminalView] = [:]
    private var accessOrder: [UUID] = []

    init() {
        E1TerminalEngine.applyAppearance()
    }

    func hasTerminal(for sessionID: UUID) -> Bool {
        terminals[sessionID] != nil
    }

    func terminalView(for session: WorktreeSession) -> E1LocalTerminalView? {
        terminals[session.id]
    }

    @discardableResult
    func ensureProcessStarted(for session: WorktreeSession) -> E1LocalTerminalView {
        if let existing = terminals[session.id] {
            touch(session.id)
            return existing
        }
        evictIfNeeded()
        let view = E1LocalTerminalView(frame: .zero)
        view.pasteImageDirectory = session.worktreePath
            .appendingPathComponent(".kobaamd/pastes", isDirectory: true)
        view.configuration = E1TerminalEngine.surfaceOptions(for: session)
        terminals[session.id] = view
        touch(session.id)
        return view
    }

    func suspendSession(id: UUID) {
        guard let view = terminals.removeValue(forKey: id) else { return }
        accessOrder.removeAll { $0 == id }
        view.removeFromSuperview()
    }

    func suspendSessions(notIn activeIDs: Set<UUID>) {
        for id in terminals.keys where !activeIDs.contains(id) {
            suspendSession(id: id)
        }
    }

    /// macOS memory pressure: drop every terminal except the active session.
    func reclaimMemory(keeping activeID: UUID?) {
        for id in terminals.keys where id != activeID {
            suspendSession(id: id)
        }
    }

    private func evictIfNeeded() {
        while terminals.count >= Self.maxActiveTerminals, let oldest = accessOrder.first {
            suspendSession(id: oldest)
        }
    }

    private func touch(_ id: UUID) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    func refreshAppearance() {
        E1TerminalEngine.applyAppearance()
        for view in terminals.values {
            view.fitToSize()
        }
    }
}