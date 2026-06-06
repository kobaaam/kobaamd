import Foundation

// MARK: - AppCommand
// Type-safe command bus. Replaces bare Notification.Name strings.
// Usage: AppCommand.save.post()  |  AppCommand.receive(.save) { ... }
enum AppCommand: String {
    case save              = "kobaamd.saveRequested"
    case newFile           = "kobaamd.newFileRequested"
    case find              = "kobaamd.findRequested"
    case openFolder        = "kobaamd.openFolderRequested"
    case toggleSidebar     = "kobaamd.sidebarToggleRequested"
    case newTab            = "kobaamd.newTabRequested"
    case formatDocument    = "kobaamd.formatDocumentRequested"
    case exportPDF              = "kobaamd.exportPDFRequested"
    case quickOpen              = "kobaamd.quickOpenRequested"
    case quickInsert            = "kobaamd.quickInsertRequested"
    case newFileFromTemplate    = "kobaamd.newFileFromTemplateRequested"
    case toggleReadingMode      = "kobaamd.toggleReadingMode"
    case toggleBold             = "kobaamd.toggleBoldRequested"
    case toggleItalic           = "kobaamd.toggleItalicRequested"
    case insertLink             = "kobaamd.insertLinkRequested"
    case e1FocusTerminal        = "kobaamd.e1FocusTerminalRequested"
    case e1FocusViewer          = "kobaamd.e1FocusViewerRequested"
    case e1FocusFiles           = "kobaamd.e1FocusFilesRequested"
    case e1ToggleMdSplit        = "kobaamd.e1ToggleMdSplitRequested"

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