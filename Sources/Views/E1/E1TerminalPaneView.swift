import AppKit
import SwiftUI
import SwiftTerm

// MARK: - E1 center pane: embedded terminal (KMD-225)

struct E1TerminalPaneView: View {
    @Bindable var coordinator: SessionCoordinator
    @Bindable var appState = AppState.shared
    @State private var terminalController = E1TerminalSessionController()

    var body: some View {
        let chrome = appState.selectedTheme
        ZStack {
            if let active = coordinator.activeTerminalSession {
                ForEach(coordinator.terminalSessions) { session in
                    let isActive = session.id == active.id
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromePaper)
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