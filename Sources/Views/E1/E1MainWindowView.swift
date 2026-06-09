import AppKit
import SwiftUI

// MARK: - E1 main window (placeholder shell, KMD-220)

struct E1MainWindowView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared
    @State private var sessionCoordinator = SessionCoordinator()
    @State private var isQuickOpenPresented = false

    @State private var leftWidth: CGFloat = E1ViewerLayoutPolicy.defaultLeftWidth
    @State private var rightFraction: CGFloat = E1MainWindowView.loadRightFraction()

    private let leftMinWidth: CGFloat = 180
    private let leftMaxWidth: CGFloat = 350
    private let rightMinWidth: CGFloat = 280
    private let centerMinWidth: CGFloat = 280
    private let dividerHitWidth: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let dividerTracks = dividerHitWidth * 2
            let remainder = max(geo.size.width - leftWidth - dividerTracks, centerMinWidth + rightMinWidth)
            let maxLeft = min(
                leftMaxWidth,
                max(leftMinWidth, geo.size.width - rightMinWidth - centerMinWidth - dividerTracks)
            )
            let rightWidth = max(rightMinWidth, remainder * rightFraction)
            let centerWidth = max(centerMinWidth, remainder - rightWidth)

            HStack(spacing: 0) {
                E1SessionRailView(coordinator: sessionCoordinator)
                    .frame(width: min(leftWidth, maxLeft))

                E1WidthDivider(
                    width: $leftWidth,
                    minWidth: leftMinWidth,
                    maxWidth: maxLeft,
                    hitWidth: dividerHitWidth,
                    dragAxis: .growOnDragRight
                )

                E1TerminalPaneView(coordinator: sessionCoordinator)
                    .frame(width: centerWidth)
                    .frame(maxHeight: .infinity)
                    .clipped()

                E1WidthDivider(
                    width: Binding(
                        get: { rightWidth },
                        set: { newWidth in
                            let newFraction = newWidth / max(remainder, 1)
                            rightFraction = min(0.75, max(0.35, newFraction))
                            Self.saveRightFraction(rightFraction)
                        }
                    ),
                    minWidth: rightMinWidth,
                    maxWidth: max(rightMinWidth, remainder - centerMinWidth),
                    hitWidth: dividerHitWidth,
                    dragAxis: .shrinkOnDragRight
                )

                E1ViewerTabsView()
                    .frame(width: rightWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appState.selectedTheme.chromePaper)
        .background(E1WindowTitleConfigurator())
        .navigationTitle("kobaamd (E1) \(AppVersion.bundleMarketing)")
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackground(appState.selectedTheme.chromeTitlebar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(appState.selectedTheme.prefersDarkChrome ? .dark : .light)
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
            Task { await appViewModel.restoreEditorSession() }
        }
        .overlay(alignment: .top) {
            if isQuickOpenPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { isQuickOpenPresented = false }
                    QuickOpenView(
                        viewModel: appViewModel.quickOpenViewModel,
                        onSelect: { url in
                            isQuickOpenPresented = false
                            guard appViewModel.quickOpenViewModel.isWithinScope(url) else { return }
                            Task { await appViewModel.openFile(url: url) }
                        },
                        onDismiss: { isQuickOpenPresented = false }
                    )
                    .padding(.top, 44)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onChange(of: rightFraction) { _, newValue in
            Self.saveRightFraction(newValue)
        }
        .onChange(of: appState.selectedTheme) { _, _ in
            NotificationCenter.default.post(name: .e1WindowChromeRefresh, object: nil)
        }
        .modifier(E1MainWindowCommandReceiver(
            appViewModel: appViewModel,
            sessionCoordinator: sessionCoordinator,
            isQuickOpenPresented: $isQuickOpenPresented
        ))
    }

    private static let rightFractionKey = "e1RightPaneFraction"

    private static func loadRightFraction() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: rightFractionKey)
        if stored > 0 { return CGFloat(stored) }
        return E1ViewerLayoutPolicy.defaultRightFraction
    }

    private static func saveRightFraction(_ value: CGFloat) {
        UserDefaults.standard.set(Double(value), forKey: rightFractionKey)
    }
}

/// タイトルバー左の白丸（システムのアイコン枠）を隠す。
private struct E1WindowTitleConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window ?? NSApp.keyWindow else { return }
            WindowChrome.configureE1Window(window)
        }
    }
}

// MARK: - E1 command receiver (minimal: folder / save / pending open)

private struct E1MainWindowCommandReceiver: ViewModifier {
    let appViewModel: AppViewModel
    let sessionCoordinator: SessionCoordinator
    @Binding var isQuickOpenPresented: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .quickOpenRequested)) { _ in
                appViewModel.refreshQuickOpenIndex()
                appViewModel.quickOpenViewModel.query = ""
                appViewModel.quickOpenViewModel.filter()
                isQuickOpenPresented = true
            }
            .onChange(of: appViewModel.fileTreeViewModel.folders) { _, _ in
                appViewModel.refreshQuickOpenIndex()
            }
            .onReceive(NotificationCenter.default.publisher(for: .e1FocusTerminalRequested)) { _ in
                NotificationCenter.default.post(name: .e1FocusTerminalPane, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .e1FocusFilesRequested)) { _ in
                NotificationCenter.default.post(name: .e1FocusFileTree, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .persistEditorSessionRequested)) { _ in
                appViewModel.persistEditorSession()
            }
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

/// 左カラム: 境界を右へドラッグすると広がる。右カラム: 境界を右へドラッグすると狭まる（VS Code 等と同じ）。
enum E1ColumnResizeDrag {
    case growOnDragRight
    case shrinkOnDragRight
}

struct E1WidthDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let hitWidth: CGFloat
    let dragAxis: E1ColumnResizeDrag
    @State private var baseWidth: CGFloat = 0
    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if isHovering || isDragging {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.kobaAccent.opacity(0.12))
                    .padding(.vertical, 4)
            }
            KobaDivider()
        }
        .frame(width: hitWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        baseWidth = width
                    }
                    let delta = value.translation.width
                    let proposed: CGFloat
                    switch dragAxis {
                    case .growOnDragRight:
                        proposed = baseWidth + delta
                    case .shrinkOnDragRight:
                        proposed = baseWidth - delta
                    }
                    width = min(maxWidth, max(minWidth, proposed))
                }
                .onEnded { _ in isDragging = false }
        )
        .onHover { inside in
            isHovering = inside
            if inside { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
        .zIndex(100)
        .accessibilityLabel("列の幅を調整")
        .help("ドラッグして列幅を変更")
    }
}