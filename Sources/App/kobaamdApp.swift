import SwiftUI
import AppKit

@main
struct kobaamdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                let recentFiles = AppState.loadRecentFiles()
                Button("New File") { AppCommand.newFile.post() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Folder…") { AppCommand.openFolder.post() }
                    .keyboardShortcut("o", modifiers: .command)
                if !recentFiles.isEmpty {
                    Menu("Open Recent") {
                        ForEach(recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                NotificationCenter.default.post(name: .openRecentNotification, object: url)
                            }
                        }
                        Divider()
                        Button("Clear Recent Files") {
                            AppState.clearRecentFiles()
                        }
                    }
                }
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

// MARK: - Notification.Name aliases

extension Notification.Name {
    static let saveRequested          = AppCommand.save.notificationName
    static let newFileRequested       = AppCommand.newFile.notificationName
    static let findRequested          = AppCommand.find.notificationName
    static let openFolderRequested    = AppCommand.openFolder.notificationName
    static let aiAssistRequested      = AppCommand.aiAssist.notificationName
    static let sidebarToggleRequested = AppCommand.toggleSidebar.notificationName
    static let gitPanelRequested      = AppCommand.toggleGitPanel.notificationName
    static let openRecentNotification = Notification.Name("kobaamd.openRecentRequested")
}

// MARK: - App Delegate (window frame save/restore)

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowFrameKey = "windowFrame"
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        subscribeToWindowNotifications()
        DispatchQueue.main.async { [weak self] in
            self?.restoreWindowFrame()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveWindowFrame()
        removeWindowNotifications()
    }

    deinit {
        removeWindowNotifications()
    }

    private func subscribeToWindowNotifications() {
        let center = NotificationCenter.default
        moveObserver = center.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveWindowFrame()
        }
        resizeObserver = center.addObserver(forName: NSWindow.didResizeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveWindowFrame()
        }
    }

    private func removeWindowNotifications() {
        let center = NotificationCenter.default
        if let moveObserver {
            center.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let resizeObserver {
            center.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
    }

    private func saveWindowFrame() {
        guard let frame = NSApp.windows.first?.frame else { return }
        AppState.shared.defaults.set(NSStringFromRect(frame), forKey: windowFrameKey)
    }

    private func restoreWindowFrame() {
        guard let window = NSApp.windows.first,
              let frameString = AppState.shared.defaults.string(forKey: windowFrameKey) else { return }
        window.setFrame(NSRectFromString(frameString), display: true)
    }
}
