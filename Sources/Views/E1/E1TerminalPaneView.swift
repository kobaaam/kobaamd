import AppKit
import SwiftUI
import SwiftTerm

// MARK: - E1 center pane: embedded terminal (KMD-225)

struct E1TerminalPaneView: View {
    @Bindable var coordinator: SessionCoordinator
    @State private var terminalController = E1TerminalSessionController()

    var body: some View {
        ZStack {
            if coordinator.sessions.isEmpty {
                terminalEmptyState
            } else {
                ForEach(coordinator.sessions) { session in
                    let isActive = coordinator.activeSessionID == session.id
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
        .background(Color.kobaPaper)
        .onChange(of: coordinator.activeSessionID) { _, newID in
            guard let id = newID,
                  let session = coordinator.sessions.first(where: { $0.id == id }) else { return }
            terminalController.ensureProcessStarted(for: session)
        }
        .onAppear {
            if let session = coordinator.activeSession {
                terminalController.ensureProcessStarted(for: session)
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(Color.kobaMute)
            Text("リポジトリを開くとターミナルが起動します")
                .font(.system(size: 12))
                .foregroundStyle(Color.kobaMute)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ターミナル。リポジトリを開いてください。")
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