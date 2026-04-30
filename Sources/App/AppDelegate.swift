import AppKit

// MARK: - App Delegate (window frame save/restore)

final class AppDelegate: NSObject, NSApplicationDelegate {
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
