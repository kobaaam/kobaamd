import SwiftUI

@main
struct kobaamdApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("kobaamd") {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(appViewModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                EmptyView()
            }
        }
    }
}
