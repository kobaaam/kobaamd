import AppKit
import SwiftUI
import SwiftTerm

// MARK: - E1 center pane: embedded terminal (KMD-225)

struct E1TerminalPaneView: View {
    @Bindable var coordinator: SessionCoordinator
    @State private var terminalController = E1TerminalSessionController()

    var body: some View {
        ZStack {
            if let active = coordinator.activeTerminalSession {
                E1TerminalRepresentable(
                    terminal: terminalController.terminalView(for: active),
                    sessionID: active.id
                ) {
                    terminalController.ensureProcessStarted(for: active)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppState.shared.selectedTheme.chromePaper)
        .onChange(of: coordinator.activeSessionID) { _, _ in
            guard let session = coordinator.activeTerminalSession else { return }
            terminalController.ensureProcessStarted(for: session)
        }
        .onAppear {
            guard let session = coordinator.activeTerminalSession else { return }
            terminalController.ensureProcessStarted(for: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .e1FocusTerminalPane)) { _ in
            guard let session = coordinator.activeTerminalSession else { return }
            let view = terminalController.terminalView(for: session)
            view.window?.makeFirstResponder(view)
        }
        .onReceive(NotificationCenter.default.publisher(for: .e1TerminalAppearanceChanged)) { _ in
            terminalController.refreshAppearance()
        }
        .onChange(of: AppState.shared.selectedTheme) { _, _ in
            terminalController.refreshAppearance()
        }
    }
}

private struct E1TerminalRepresentable: NSViewRepresentable {
    let terminal: E1LocalTerminalView
    let sessionID: UUID
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> E1LocalTerminalView {
        terminal.translatesAutoresizingMaskIntoConstraints = false
        onActivate()
        context.coordinator.activatedSessionID = sessionID
        return terminal
    }

    func updateNSView(_ nsView: E1LocalTerminalView, context: Context) {
        guard context.coordinator.activatedSessionID != sessionID else { return }
        context.coordinator.activatedSessionID = sessionID
        onActivate()
    }

    final class Coordinator {
        var activatedSessionID: UUID?
    }
}