import AppKit
import SwiftUI
import GhosttyTerminal

// MARK: - E1 center pane: embedded terminal (KMD-225)

struct E1TerminalPaneView: View {
    @Bindable var coordinator: SessionCoordinator
    @State private var terminalController = E1TerminalSessionController()

    var body: some View {
        ZStack {
            ForEach(coordinator.terminalSessions) { session in
                if terminalController.hasTerminal(for: session.id) {
                    let isActive = session.id == coordinator.activeSessionID
                    E1TerminalRepresentable(
                        terminal: terminalController.terminalView(for: session)!
                    )
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppState.shared.selectedTheme.chromePaper)
        .onChange(of: coordinator.activeSessionID) { _, _ in
            focusActiveTerminal()
        }
        .onAppear {
            focusActiveTerminal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .e1FocusTerminalPane)) { _ in
            focusActiveTerminal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .e1TerminalAppearanceChanged)) { _ in
            terminalController.refreshAppearance()
        }
        .onChange(of: AppState.shared.selectedTheme) { _, _ in
            terminalController.refreshAppearance()
        }
    }

    private func focusActiveTerminal() {
        guard let session = coordinator.activeTerminalSession else { return }
        let view = terminalController.ensureProcessStarted(for: session)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            view.fitToSize()
        }
    }
}

private struct E1TerminalRepresentable: NSViewRepresentable {
    let terminal: E1LocalTerminalView

    func makeNSView(context: Context) -> E1LocalTerminalView {
        terminal.translatesAutoresizingMaskIntoConstraints = false
        return terminal
    }

    func updateNSView(_ nsView: E1LocalTerminalView, context: Context) {
        nsView.fitToSize()
    }
}