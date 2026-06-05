import AppKit
import SwiftUI

// MARK: - E1 main window (placeholder shell, KMD-220)

struct E1MainWindowView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var sessionCoordinator = SessionCoordinator()

    @State private var leftWidth: CGFloat = 240
    @State private var rightWidth: CGFloat = 360

    private let leftMinWidth: CGFloat = 200
    private let rightMinWidth: CGFloat = 280

    var body: some View {
        HStack(spacing: 0) {
            E1SessionRailView(coordinator: sessionCoordinator)
                .frame(width: leftWidth)

            E1WidthDivider(
                width: $leftWidth,
                minWidth: leftMinWidth,
                dragMultiplier: 1
            )

            E1TerminalPlaceholderView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            E1WidthDivider(
                width: $rightWidth,
                minWidth: rightMinWidth,
                dragMultiplier: -1
            )

            E1ViewerPlaceholderView()
                .frame(width: rightWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaPaper)
        .navigationTitle("kobaamd (E1)")
        .frame(minWidth: 720, minHeight: 400)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    NotificationCenter.default.post(name: .openFolderRequested, object: nil)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open Folder (⌘O)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .saveRequested, object: nil)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save (⌘S)")
            }
        }
        .onAppear {
            sessionCoordinator.attach(appViewModel: appViewModel)
            Task { await sessionCoordinator.bootstrapIfNeeded() }
        }
        .modifier(E1MainWindowCommandReceiver(
            appViewModel: appViewModel,
            sessionCoordinator: sessionCoordinator
        ))
    }
}

// MARK: - E1 command receiver (minimal: folder / save / pending open)

private struct E1MainWindowCommandReceiver: ViewModifier {
    let appViewModel: AppViewModel
    let sessionCoordinator: SessionCoordinator

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
                if AppState.shared.autoFormatOnSave {
                    appViewModel.formatCurrentDocument()
                }
                appViewModel.saveCurrentFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { _ in
                openGitRepositoryFolder()
            }
            .onChange(of: AppState.shared.pendingOpenFileURL) { _, fileURL in
                guard let url = fileURL else { return }
                AppState.shared.pendingOpenFileURL = nil
                Task {
                    await appViewModel.openFile(url: url)
                }
            }
    }

    private func openGitRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "リポジトリを開く"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await sessionCoordinator.handleFolderOpened(url)
        }
    }
}

// MARK: - Draggable width divider (ADR-0010 pattern)

struct E1WidthDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    /// `1` when divider is to the right of the pane (left rail); `-1` for right viewer pane.
    let dragMultiplier: CGFloat
    @State private var baseWidth: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        KobaDivider()
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            baseWidth = width
                        }
                        let delta = value.translation.width * dragMultiplier
                        width = max(minWidth, baseWidth + delta)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }
}