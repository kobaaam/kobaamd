import SwiftUI
import AppKit
import Sparkle
@testable import kobaamdLib

@main
struct kobaamdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var appViewModel = AppViewModel()
    @State private var updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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
                Divider()
                Button("Confluence に同期") { AppCommand.confluenceSync.post() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Confluence ページ設定...") { AppCommand.confluencePageSettings.post() }
            }
            CommandGroup(after: .textEditing) {
                Button("Find & Replace") { AppCommand.find.post() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("AI アシスト…") { AppCommand.aiAssist.post() }
                    .keyboardShortcut("e", modifiers: .command)
                Button("AI チャット") { AppCommand.aiChat.post() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("AI 生成をキャンセル") { AppCommand.cancelAIGeneration.post() }
                    .keyboardShortcut(".", modifiers: .command)
                Button("クイックインサート") { AppCommand.quickInsert.post() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("Format") {
                Button("Format Document") { AppCommand.formatDocument.post() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) {
                Button("Quick Open…") { AppCommand.quickOpen.post() }
                    .keyboardShortcut("p", modifiers: .command)
            }
            CommandGroup(before: .sidebar) {
                Button("サイドバーの表示/非表示") { AppCommand.toggleSidebar.post() }
                    .keyboardShortcut("b", modifiers: .command)
                Divider()
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .help) {
                Button("kobaamd ヘルプ") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(appViewModel)
        }

        Window("kobaamd ヘルプ", id: "help") {
            HelpWindowView()
        }
        .defaultSize(width: 640, height: 480)
    }
}
