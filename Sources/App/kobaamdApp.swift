import SwiftUI

@main
struct kobaamdApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("kobaamd") {
            MainWindowView(appViewModel: appViewModel)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
