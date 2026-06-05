import AppKit
import SwiftUI

// MARK: - E1 main window (placeholder shell, KMD-220)

struct E1MainWindowView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var sessionCoordinator = SessionCoordinator()

    @State private var leftWidth: CGFloat = 240
    @State private var rightWidth: CGFloat = 360

    private let leftMinWidth: CGFloat = 180
    private let rightMinWidth: CGFloat = 240
    private let centerMinWidth: CGFloat = 280
    private let dividerHitWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let dividerTracks = dividerHitWidth * 2
            let maxLeft = max(
                leftMinWidth,
                geo.size.width - rightWidth - centerMinWidth - dividerTracks
            )
            let maxRight = max(
                rightMinWidth,
                geo.size.width - leftWidth - centerMinWidth - dividerTracks
            )

            HStack(spacing: 0) {
                E1SessionRailView(coordinator: sessionCoordinator)
                    .frame(width: min(leftWidth, maxLeft))

                E1WidthDivider(
                    width: $leftWidth,
                    minWidth: leftMinWidth,
                    maxWidth: maxLeft,
                    hitWidth: dividerHitWidth
                )

                E1TerminalPaneView(coordinator: sessionCoordinator)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                E1WidthDivider(
                    width: $rightWidth,
                    minWidth: rightMinWidth,
                    maxWidth: maxRight,
                    hitWidth: dividerHitWidth
                )

                E1ViewerTabsView()
                    .frame(width: min(rightWidth, maxRight))
            }
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
                    Image(systemName: "plus.folder")
                }
                .help("セッションを追加 (⌘O)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newFileRequested, object: nil)
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("New File (⌘N)")
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
            sessionCoordinator.bootstrapIfNeeded()
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
                _ = sessionCoordinator.addLocalSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newFileRequested)) { _ in
                createNewFileInActiveSession()
            }
            .onChange(of: AppState.shared.pendingOpenFileURL) { _, fileURL in
                guard let url = fileURL else { return }
                AppState.shared.pendingOpenFileURL = nil
                Task {
                    await appViewModel.openFile(url: url)
                }
            }
    }

    private func createNewFileInActiveSession() {
        guard sessionCoordinator.activeSession != nil else { return }
        do {
            let url = try appViewModel.fileTreeViewModel.createNewFileInRoot()
            Task { await appViewModel.openNewArtifact(url: url) }
        } catch {
            appViewModel.showAppError(.fileWriteFailed(
                url: appViewModel.fileTreeViewModel.rootURL ?? URL(fileURLWithPath: "/"),
                underlying: error
            ))
        }
    }
}

// MARK: - Draggable width divider (ADR-0010 pattern)

struct E1WidthDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let hitWidth: CGFloat
    @State private var baseWidth: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        ZStack {
            KobaDivider()
        }
        .frame(width: hitWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        baseWidth = width
                    }
                    let proposed = baseWidth + value.translation.width
                    width = min(maxWidth, max(minWidth, proposed))
                }
                .onEnded { _ in isDragging = false }
        )
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
        .zIndex(1)
        .accessibilityLabel("列の幅を調整")
    }
}