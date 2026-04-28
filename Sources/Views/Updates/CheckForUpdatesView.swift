import SwiftUI
import Sparkle

// MARK: - CheckForUpdatesView
// ヘルプメニューに表示する「アップデートを確認...」メニュー項目

struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    @State private var canCheckForUpdates = false

    var body: some View {
        Button("アップデートを確認...") {
            updater.checkForUpdates()
        }
        .disabled(!canCheckForUpdates)
        .onAppear {
            canCheckForUpdates = !updater.sessionInProgress
        }
    }
}
