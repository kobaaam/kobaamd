import Foundation

// MARK: - AppCommand
// Type-safe command bus. Replaces bare Notification.Name strings.
// Usage: AppCommand.save.post()  |  AppCommand.receive(.save) { ... }
enum AppCommand: String {
    case save              = "kobaamd.saveRequested"
    case newFile           = "kobaamd.newFileRequested"
    case find              = "kobaamd.findRequested"
    case openFolder        = "kobaamd.openFolderRequested"
    case aiAssist          = "kobaamd.aiAssistRequested"
    case toggleSidebar     = "kobaamd.sidebarToggleRequested"
    case newTab            = "kobaamd.newTabRequested"
    case formatDocument    = "kobaamd.formatDocumentRequested"
    case exportPDF              = "kobaamd.exportPDFRequested"
    case confluenceSync         = "kobaamd.confluenceSyncRequested"
    case confluencePageSettings = "kobaamd.confluencePageSettingsRequested"

    var notificationName: Notification.Name { Notification.Name(rawValue) }

    func post() {
        NotificationCenter.default.post(name: notificationName, object: nil)
    }

    static func receive(_ command: AppCommand, perform action: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: command.notificationName, object: nil, queue: .main) { _ in
            action()
        }
    }
}
