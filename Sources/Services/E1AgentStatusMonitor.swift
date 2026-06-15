import AppKit
import Foundation
import Observation
import UserNotifications

/// アクティブ E1 ターミナルを低頻度でサンプリング（エージェント状態 + ディスク transcript）。
/// バックグラウンド時は停止し、SCREEN 読み取りは transcript 用にのみ間引く。
@Observable
@MainActor
final class E1AgentStatusMonitor {
    private(set) var statuses: [UUID: E1AgentStatus] = [:]

    private weak var terminalController: E1TerminalSessionController?
    private weak var sessionCoordinator: SessionCoordinator?
    private var timer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var lastViewportHashes: [UUID: Int] = [:]
    private var lastScreenSnapshots: [UUID: E1TerminalScreenSnapshot] = [:]
    private var lastNotifiedBlocked: Set<UUID> = []
    private var tickCount = 0
    private var isPaused = false
    private var isRefreshing = false

    func attach(
        terminalController: E1TerminalSessionController,
        sessionCoordinator: SessionCoordinator
    ) {
        self.terminalController = terminalController
        self.sessionCoordinator = sessionCoordinator
        subscribeToAppLifecycle()
        resumeSampling()
    }

    func detach() {
        pauseSampling()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
        terminalController = nil
        sessionCoordinator = nil
    }

    func status(for sessionID: UUID) -> E1AgentStatus {
        statuses[sessionID] ?? .unknown
    }

    private func subscribeToAppLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.pauseSampling() }
            },
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.resumeSampling() }
            },
        ]
    }

    private func pauseSampling() {
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    private func resumeSampling() {
        guard !isPaused else {
            isPaused = false
            startTimerIfNeeded()
            return
        }
        startTimerIfNeeded()
    }

    private func startTimerIfNeeded() {
        guard timer == nil, terminalController != nil, sessionCoordinator != nil else { return }
        refresh()
        let interval = E1TerminalMemoryPolicy.agentStatusPollInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard !isPaused, !isRefreshing else { return }
        guard let terminalController, let sessionCoordinator else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        tickCount += 1
        let shouldCaptureTranscript = tickCount.isMultiple(
            of: E1TerminalMemoryPolicy.transcriptEveryNTicks
        )
        let activeID = sessionCoordinator.activeSessionID

        var nextStatuses = statuses
        for session in sessionCoordinator.sessions {
            guard let terminal = terminalController.terminalView(for: session) else {
                continue
            }
            if let viewport = terminal.readViewportText() {
                let isActive = session.id == activeID
                if let parsed = updateAgentStatus(
                    for: session,
                    viewport: viewport,
                    into: &nextStatuses
                ) {
                    maybeNotifyBlocked(
                        session: session,
                        status: parsed,
                        isActiveSession: isActive
                    )
                }
            }

            if shouldCaptureTranscript,
               session.id == activeID,
               let screen = terminal.readScreenText() {
                captureTranscript(for: session, screen: screen)
            }
        }
        statuses = nextStatuses

        let activeIDs = Set(sessionCoordinator.sessions.map(\.id))
        lastViewportHashes = lastViewportHashes.filter { activeIDs.contains($0.key) }
        lastScreenSnapshots = lastScreenSnapshots.filter { activeIDs.contains($0.key) }
    }

    @discardableResult
    private func updateAgentStatus(
        for session: WorktreeSession,
        viewport: String,
        into statuses: inout [UUID: E1AgentStatus]
    ) -> E1AgentStatus? {
        var hasher = Hasher()
        hasher.combine(viewport)
        let hash = hasher.finalize()
        if hash == lastViewportHashes[session.id], let cached = self.statuses[session.id] {
            statuses[session.id] = cached
            return nil
        }
        lastViewportHashes[session.id] = hash

        let parsed = E1AgentStatusParser.parse(viewportText: viewport)
        statuses[session.id] = parsed
        return parsed
    }

    private func captureTranscript(for session: WorktreeSession, screen: String) {
        let previous = lastScreenSnapshots[session.id]
        do {
            if let next = try E1TerminalTranscriptStore.appendDelta(
                previousSnapshot: previous,
                currentScreen: screen,
                to: session.worktreePath
            ) {
                lastScreenSnapshots[session.id] = next
            }
        } catch {
            NSLog("E1AgentStatusMonitor: transcript failed for \(session.id): \(error)")
        }
    }

    private func maybeNotifyBlocked(
        session: WorktreeSession,
        status: E1AgentStatus,
        isActiveSession: Bool
    ) {
        guard status == .blocked else {
            lastNotifiedBlocked.remove(session.id)
            return
        }
        guard AppState.shared.e1NotifyWhenAgentBlocked else { return }
        guard !isActiveSession else { return }
        guard !lastNotifiedBlocked.contains(session.id) else { return }

        lastNotifiedBlocked.insert(session.id)
        postBlockedNotification(for: session)
    }

    private func postBlockedNotification(for session: WorktreeSession) {
        let content = UNMutableNotificationContent()
        content.title = "エージェントが入力待ち"
        content.body = "\(session.name) — 承認または回答が必要です"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "e1.agent.blocked.\(session.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}