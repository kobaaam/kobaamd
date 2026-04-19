import SwiftUI

@main
struct kobaamdApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
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
                Button("Open Folder…") {
                    NotificationCenter.default.post(name: .openFolderRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find & Replace") {
                    NotificationCenter.default.post(name: .findRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("AI アシスト…") {
                    NotificationCenter.default.post(name: .aiAssistRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
            CommandGroup(before: .sidebar) {
                Button("サイドバーの表示/非表示") {
                    NotificationCenter.default.post(name: .sidebarToggleRequested, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                Button("Git パネル") {
                    NotificationCenter.default.post(name: .gitPanelRequested, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
                Divider()
            }
        }

        // Settings window (⌘,)
        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let saveRequested         = Notification.Name("kobaamd.saveRequested")
    static let newFileRequested      = Notification.Name("kobaamd.newFileRequested")
    static let findRequested         = Notification.Name("kobaamd.findRequested")
    static let openFolderRequested   = Notification.Name("kobaamd.openFolderRequested")
    static let aiAssistRequested     = Notification.Name("kobaamd.aiAssistRequested")
    static let sidebarToggleRequested = Notification.Name("kobaamd.sidebarToggleRequested")
    static let gitPanelRequested      = Notification.Name("kobaamd.gitPanelRequested")
}
