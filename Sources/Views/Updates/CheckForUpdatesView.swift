import AppKit
import SwiftUI
import Combine
import Sparkle

// MARK: - CheckForUpdatesView
// ヘルプメニューに表示する「アップデートを確認...」メニュー項目

struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    @StateObject private var state = UpdateCheckState()

    var body: some View {
        Button("アップデートを確認...") {
            NSApp.activate()
            DispatchQueue.main.async {
                updater.checkForUpdates()
            }
        }
        .disabled(!state.canCheckForUpdates)
        .onAppear {
            state.canCheckForUpdates = updater.canCheckForUpdates
            if state.cancellable == nil {
                state.cancellable = updater.publisher(for: \.canCheckForUpdates)
                    .receive(on: DispatchQueue.main)
                    .assign(to: \.canCheckForUpdates, on: state)
            }
        }
    }
}

private final class UpdateCheckState: ObservableObject {
    @Published var canCheckForUpdates = false
    var cancellable: AnyCancellable?
}
