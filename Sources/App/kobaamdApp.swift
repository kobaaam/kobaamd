import SwiftUI
import AppKit

@main
struct kobaamdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("kobaamd") {
            MainWindowView()
                .environment(appViewModel)
                .alert("Error", isPresented: Bindable(appViewModel).showError) {
                    Button("OK") {}
                } message: {
                    Text(appViewModel.errorMessage ?? "")
                }
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                let recentFiles = AppState.loadRecentFiles()
                Button("New Tab") { AppCommand.newTab.post() }
                    .keyboardShortcut("t", modifiers: .command)
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
    static let newTabRequested        = AppCommand.newTab.notificationName
    static let openRecentNotification = Notification.Name("kobaamd.openRecentRequested")
    static let openFileRequested      = Notification.Name("kobaamd.openFileRequested")
}

// MARK: - App Delegate (window frame save/restore)

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowFrameKey = "windowFrame"
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    /// Finder ダブルクリック（URL配列版・現代的 API）
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first,
              FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
        AppState.shared.pendingOpenFileURL = url
        NSApp.activate(ignoringOtherApps: true)
        application.windows.first?.makeKeyAndOrderFront(nil)
    }

    /// Finder ダブルクリック（レガシー単一ファイル API）。true を返して新規ウィンドウ生成を抑制。
    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return false }
        AppState.shared.pendingOpenFileURL = url
        NSApp.activate(ignoringOtherApps: true)
        application.windows.first?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ツールチップを 0.5秒で表示（デフォルト ~1秒）
        UserDefaults.standard.set(0.5, forKey: "NSToolTipDelay")
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
