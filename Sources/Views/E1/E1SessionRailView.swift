import SwiftUI

// MARK: - E1 left rail: Sessions (top) + Files (bottom)

struct E1SessionRailView: View {
    @Bindable var coordinator: SessionCoordinator
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared

    private let sessionsFraction: CGFloat = 0.42

    var body: some View {
        @Bindable var fileTree = appViewModel.fileTreeViewModel
        GeometryReader { geo in
            let sessionsHeight = max(80, geo.size.height * sessionsFraction)
            VStack(spacing: 0) {
                E1SessionsListView(coordinator: coordinator)
                    .frame(height: sessionsHeight)

                KobaHDivider()

                E1ScopedFileTreeView(fileTreeViewModel: fileTree)
                    .frame(maxHeight: .infinity)
                    .id(coordinator.activeSessionID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appState.selectedTheme.chromeSurface)
    }
}