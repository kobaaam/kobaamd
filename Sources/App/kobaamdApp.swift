import SwiftUI
import AppKit

struct kobaamdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("kobaamd") {
            Group {
                if AppState.shared.useE1Shell {
                    E1MainWindowView()
                } else {
                    MainWindowView()
                }
            }
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
                Button("New File from Template\u{2026}") { AppCommand.newFileFromTemplate.post() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
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
            CommandGroup(after: .saveItem) {
                Button("PDFに書き出し...") { AppCommand.exportPDF.post() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Find & Replace") { AppCommand.find.post() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("クイックインサート") { AppCommand.quickInsert.post() }
                    .keyboardShortcut("k", modifiers: [.command, .option])
            }
            CommandMenu("Format") {
                Button("Bold") { AppCommand.toggleBold.post() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { AppCommand.toggleItalic.post() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Add Link") { AppCommand.insertLink.post() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Format Document") { AppCommand.formatDocument.post() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) {
                Button("Quick Open…") { AppCommand.quickOpen.post() }
                    .keyboardShortcut("p", modifiers: .command)
            }
            CommandGroup(before: .sidebar) {
                Button("サイドバーの表示/非表示") { AppCommand.toggleSidebar.post() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("読書モード") { AppCommand.toggleReadingMode.post() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
            }
            CommandMenu("表示") {
                Button("コードフォントを大きく") {
                    AppState.shared.adjustCodeFontSize(by: AppState.CodeFontSize.step)
                }
                .keyboardShortcut("=", modifiers: .command)
                Button("コードフォントを小さく") {
                    AppState.shared.adjustCodeFontSize(by: -AppState.CodeFontSize.step)
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("コードフォントを既定値に戻す") {
                    AppState.shared.resetCodeFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            CommandMenu("E1") {
                Button("フォーカス: ターミナル") { AppCommand.e1FocusTerminal.post() }
                    .keyboardShortcut("1", modifiers: .command)
                Button("フォーカス: ビューア") { AppCommand.e1FocusViewer.post() }
                    .keyboardShortcut("2", modifiers: .command)
                Button("フォーカス: ファイル") { AppCommand.e1FocusFiles.post() }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Markdown Split の表示/非表示") { AppCommand.e1ToggleMdSplit.post() }
                    .keyboardShortcut("\\", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("kobaamd ヘルプ") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(appViewModel)
        }

        Window("kobaamd ヘルプ", id: "help") {
            HelpWindowView()
        }
        .defaultSize(width: 640, height: 480)
    }
}

// MARK: - Notification.Name aliases

extension Notification.Name {
    static let saveRequested          = AppCommand.save.notificationName
    static let newFileRequested       = AppCommand.newFile.notificationName
    static let findRequested          = AppCommand.find.notificationName
    static let openFolderRequested    = AppCommand.openFolder.notificationName
    static let quickInsertRequested   = AppCommand.quickInsert.notificationName
    static let sidebarToggleRequested = AppCommand.toggleSidebar.notificationName
    static let toggleReadingModeRequested = AppCommand.toggleReadingMode.notificationName
    static let newTabRequested          = AppCommand.newTab.notificationName
    static let formatDocumentRequested = AppCommand.formatDocument.notificationName
    static let toggleBoldRequested      = AppCommand.toggleBold.notificationName
    static let toggleItalicRequested    = AppCommand.toggleItalic.notificationName
    static let insertLinkRequested      = AppCommand.insertLink.notificationName
    static let openRecentNotification  = Notification.Name("kobaamd.openRecentRequested")
    static let openFileRequested      = Notification.Name("kobaamd.openFileRequested")
    static let cursorBlockChanged     = Notification.Name("kobaamd.cursorBlockChanged")
    static let jumpToLine             = Notification.Name("kobaamd.jumpToLine")
    static let previewScrollRatioChanged = Notification.Name("kobaamd.previewScrollRatioChanged")
    static let e1TerminalAppearanceChanged = Notification.Name("kobaamd.e1TerminalAppearanceChanged")
    static let exportPDFRequested             = AppCommand.exportPDF.notificationName
    static let exportPDFWithURL               = Notification.Name("kobaamd.exportPDFWithURL")
    static let exportPDFCompleted             = Notification.Name("kobaamd.exportPDFCompleted")
    static let quickOpenRequested              = AppCommand.quickOpen.notificationName
    static let e1FocusTerminalRequested        = AppCommand.e1FocusTerminal.notificationName
    static let e1FocusViewerRequested          = AppCommand.e1FocusViewer.notificationName
    static let e1FocusFilesRequested           = AppCommand.e1FocusFiles.notificationName
    static let e1ToggleMdSplitRequested          = AppCommand.e1ToggleMdSplit.notificationName
    static let e1FocusEditorRequested          = Notification.Name("kobaamd.e1FocusEditorRequested")
    static let e1FocusTerminalPane             = Notification.Name("kobaamd.e1FocusTerminalPane")
    static let e1FocusFileTree                 = Notification.Name("kobaamd.e1FocusFileTree")
    static let newFileFromTemplateRequested     = AppCommand.newFileFromTemplate.notificationName
    static let insertSnippetAtCursor           = Notification.Name("kobaamd.insertSnippetAtCursor")
    static let persistEditorSessionRequested   = Notification.Name("kobaamd.persistEditorSessionRequested")
}

// MARK: - App Delegate (window frame save/restore)

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowFrameKey = "windowFrame"
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var windowChromeObservers: [NSObjectProtocol] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first,
              FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
        AppState.shared.pendingOpenFileURL = url
        NSApp.activate(ignoringOtherApps: true)
        application.windows.first?.makeKeyAndOrderFront(nil)
    }

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
        subscribeToWindowChromeNotifications()
        DispatchQueue.main.async { [weak self] in
            self?.restoreWindowFrame()
            NSApp.windows.forEach(WindowChrome.configureE1Window)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .persistEditorSessionRequested, object: nil)
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

    private func subscribeToWindowChromeNotifications() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResizeNotification,
        ]
        windowChromeObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let window = notification.object as? NSWindow else { return }
                WindowChrome.configureE1Window(window)
            }
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
        for observer in windowChromeObservers {
            center.removeObserver(observer)
        }
        windowChromeObservers.removeAll()
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