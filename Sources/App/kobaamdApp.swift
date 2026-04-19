import SwiftUI

@main
struct kobaamdApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(appViewModel)
                .alert("Error", isPresented: Bindable(appViewModel).showError) {
                    Button("OK") {}
                } message: {
                    Text(appViewModel.errorMessage ?? "")
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    NotificationCenter.default.post(name: .newFileRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let saveRequested = Notification.Name("kobaamd.saveRequested")
    static let newFileRequested = Notification.Name("kobaamd.newFileRequested")
}
