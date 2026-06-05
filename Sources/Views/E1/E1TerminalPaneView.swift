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

            if coordinator.sessions.isEmpty {
                terminalGitHint
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

    /// git worktree セッションがまだ無いときの薄いヒント（PTY は Local で起動済み）。
    private var terminalGitHint: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("フォルダから git リポジトリを開くと worktree セッションが追加されます")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.kobaMute.opacity(0.9))
                    .padding(8)
                    .background(Color.kobaPaper.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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