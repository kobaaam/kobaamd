import Foundation

// MARK: - Notification.Name aliases

extension Notification.Name {
    static let saveRequested          = AppCommand.save.notificationName
    static let newFileRequested       = AppCommand.newFile.notificationName
    static let findRequested          = AppCommand.find.notificationName
    static let openFolderRequested    = AppCommand.openFolder.notificationName
    static let aiAssistRequested      = AppCommand.aiAssist.notificationName
    static let aiChatRequested        = AppCommand.aiChat.notificationName
    static let quickInsertRequested   = AppCommand.quickInsert.notificationName
    static let sidebarToggleRequested = AppCommand.toggleSidebar.notificationName
    static let newTabRequested          = AppCommand.newTab.notificationName
    static let formatDocumentRequested = AppCommand.formatDocument.notificationName
    static let openRecentNotification  = Notification.Name("kobaamd.openRecentRequested")
    static let openFileRequested      = Notification.Name("kobaamd.openFileRequested")
    static let cursorBlockChanged     = Notification.Name("kobaamd.cursorBlockChanged")
    static let aiInlineRequested      = Notification.Name("kobaamd.aiInlineRequested")
    static let jumpToLine             = Notification.Name("kobaamd.jumpToLine")
    static let exportPDFRequested             = AppCommand.exportPDF.notificationName
    static let exportPDFWithURL               = Notification.Name("kobaamd.exportPDFWithURL")
    static let exportPDFCompleted             = Notification.Name("kobaamd.exportPDFCompleted")
    static let confluenceSyncRequested         = AppCommand.confluenceSync.notificationName
    static let confluencePageSettingsRequested = AppCommand.confluencePageSettings.notificationName
    static let quickOpenRequested              = AppCommand.quickOpen.notificationName
    static let cancelAIGenerationRequested     = AppCommand.cancelAIGeneration.notificationName
    static let newFileFromTemplateRequested     = AppCommand.newFileFromTemplate.notificationName
    static let insertSnippetAtCursor           = Notification.Name("kobaamd.insertSnippetAtCursor")
}
