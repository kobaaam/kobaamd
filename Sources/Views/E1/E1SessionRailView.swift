import SwiftUI

// MARK: - E1 left rail: Sessions (top) + Files (bottom)

struct E1SessionRailView: View {
    @Bindable var coordinator: SessionCoordinator
    @Environment(AppViewModel.self) private var appViewModel

    private let sessionsFraction: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            let sessionsHeight = max(80, geo.size.height * sessionsFraction)
            VStack(spacing: 0) {
                E1SessionsListView(coordinator: coordinator)
                    .frame(height: sessionsHeight)

                KobaHDivider()

                E1ScopedFileTreeView(fileTreeViewModel: appViewModel.fileTreeViewModel)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaSurface)
    }
}