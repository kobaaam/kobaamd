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
                Button("New File") { AppCommand.newFile.post() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Folder…") { AppCommand.openFolder.post() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { AppCommand.save.post() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find & Replace") { AppCommand.find.post() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("AI アシスト…") { AppCommand.aiAssist.post() }
                    .keyboardShortcut("e", modifiers: .command)
            }
            CommandGroup(before: .sidebar) {
                Button("サイドバーの表示/非表示") { AppCommand.toggleSidebar.post() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Git パネル") { AppCommand.toggleGitPanel.post() }
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

// Notification.Name aliases for views that still use .onReceive(NotificationCenter...)
// These resolve to the same underlying names as AppCommand cases.
extension Notification.Name {
    static let saveRequested          = AppCommand.save.notificationName
    static let newFileRequested       = AppCommand.newFile.notificationName
    static let findRequested          = AppCommand.find.notificationName
    static let openFolderRequested    = AppCommand.openFolder.notificationName
    static let aiAssistRequested      = AppCommand.aiAssist.notificationName
    static let sidebarToggleRequested = AppCommand.toggleSidebar.notificationName
    static let gitPanelRequested      = AppCommand.toggleGitPanel.notificationName
}
