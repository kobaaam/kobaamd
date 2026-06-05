import AppKit
import SwiftUI
import SwiftTerm

// MARK: - E1 center pane: embedded terminal (KMD-225)

struct E1TerminalPaneView: View {
    @Bindable var coordinator: SessionCoordinator
    @State private var terminalController = E1TerminalSessionController()

    var body: some View {
        ZStack {
            ForEach(coordinator.terminalSessions) { session in
                let isActive = session.id == coordinator.activeTerminalSession.id
                E1TerminalRepresentable(
                    terminal: terminalController.terminalView(for: session),
                    isActive: isActive
                ) {
                    if isActive {
                        terminalController.ensureProcessStarted(for: session)
                    }
                }
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaPaper)
        .onChange(of: coordinator.activeSessionID) { _, _ in
            terminalController.ensureProcessStarted(for: coordinator.activeTerminalSession)
        }
        .onAppear {
            terminalController.ensureProcessStarted(for: coordinator.activeTerminalSession)
        }
    }
}

private struct E1TerminalRepresentable: NSViewRepresentable {
    let terminal: LocalProcessTerminalView
    let isActive: Bool
    let onActivate: () -> Void

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminal.translatesAutoresizingMaskIntoConstraints = false
        onActivate()
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if isActive {
            onActivate()
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}