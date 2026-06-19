import Foundation
import Observation

@Observable final class AppState {
    /// Finder ダブルクリック / ドロップで開くべきファイル URL。
    /// AppDelegate がセットし、MainWindowView の onChange で検知してタブを開く。
    var pendingOpenFileURL: URL? = nil

    // Inject UserDefaults for testability; defaults to .standard in production.
    let defaults: UserDefaults

    static let shared = AppState()

    private static let lastFolderKey      = "lastFolderURL"
    private static let lastFileKey        = "lastFileURL"
    private static let recentFilesKey     = "recentFiles"
    private static let workspaceBookmarks = "workspaceFolderBookmarks"
    private static let maxRecentFiles     = 10
    private static let selectedThemeKey   = "selectedColorTheme"
    private static let terminalThemeUnifiedKey = "terminalThemeUnifiedToDark_v1"
    private static let terminalFontSizeKey = "terminalFontSize"
    private static let showHiddenFilesKey = "showHiddenFiles"
    static let indexDependencyDirectoriesKey = "indexDependencyDirectories"
    static let htmlPreviewEngineKey = "htmlPreviewEngine"

    enum HTMLPreviewEngine: String, CaseIterable, Identifiable {
        case chromium
        case webKit

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .chromium: return "Chromium（Google Chrome 等）"
            case .webKit: return "WebKit（アプリ内）"
            }
        }
    }

    enum CodeFontSize {
        static let min: Double = 11
        static let max: Double = 22
        static let defaultSize: Double = 12
        static let step: Double = 1
    }
    private static let e1LocalSessionsKey = "e1LocalSessions"
    private static let e1ActiveSessionIDKey = "e1ActiveSessionID"
    private static let openTabURLsKey = "openTabURLs"
    private static let activeTabURLKey = "activeTabURL"

    var selectedTheme: ColorTheme {
        didSet {
            defaults.set(selectedTheme.rawValue, forKey: Self.selectedThemeKey)
        }
    }

    /// ターミナルとエディタの等幅フォントサイズ（pt）。既定 12pt。
    var terminalFontSize: Double {
        didSet {
            defaults.set(terminalFontSize, forKey: Self.terminalFontSizeKey)
        }
    }

    /// ファイルツリーにドット始まりの項目（`.scratch`, `.git` 等）を含める。
    var showHiddenFiles: Bool {
        didSet {
            defaults.set(showHiddenFiles, forKey: Self.showHiddenFilesKey)
        }
    }

    /// `node_modules` / `dist` / `.git` 等をツリー・全文検索インデックスに含める（既定 OFF）。
    var indexDependencyDirectories: Bool {
        didSet {
            defaults.set(indexDependencyDirectories, forKey: Self.indexDependencyDirectoriesKey)
        }
    }

    /// HTML プレビューに使うブラウザエンジン（既定: Chromium）。
    var htmlPreviewEngine: HTMLPreviewEngine {
        didSet {
            defaults.set(htmlPreviewEngine.rawValue, forKey: Self.htmlPreviewEngineKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.selectedThemeKey) ?? ColorTheme.e1Recommended.rawValue
        var theme = ColorTheme(rawValue: raw) ?? .e1Recommended
        if !defaults.bool(forKey: Self.terminalThemeUnifiedKey) {
            if theme == .solarizedDark {
                theme = .e1Recommended
                defaults.set(ColorTheme.e1Recommended.rawValue, forKey: Self.selectedThemeKey)
            }
            defaults.set(true, forKey: Self.terminalThemeUnifiedKey)
        }
        self.selectedTheme = theme
        let storedFontSize = defaults.double(forKey: Self.terminalFontSizeKey)
        self.terminalFontSize = storedFontSize > 0 ? storedFontSize : Self.CodeFontSize.defaultSize
        self.showHiddenFiles = defaults.bool(forKey: Self.showHiddenFilesKey)
        self.indexDependencyDirectories = defaults.bool(forKey: Self.indexDependencyDirectoriesKey)
        let engineRaw = defaults.string(forKey: Self.htmlPreviewEngineKey) ?? HTMLPreviewEngine.chromium.rawValue
        self.htmlPreviewEngine = HTMLPreviewEngine(rawValue: engineRaw) ?? .chromium
    }

    func adjustCodeFontSize(by delta: Double) {
        let next = min(Self.CodeFontSize.max, max(Self.CodeFontSize.min, terminalFontSize + delta))
        guard next != terminalFontSize else { return }
        terminalFontSize = next
        Self.postCodeFontAppearanceChanged()
    }

    func resetCodeFontSize() {
        guard terminalFontSize != Self.CodeFontSize.defaultSize else { return }
        terminalFontSize = Self.CodeFontSize.defaultSize
        Self.postCodeFontAppearanceChanged()
    }

    static func postCodeFontAppearanceChanged() {
        NotificationCenter.default.post(name: .e1TerminalAppearanceChanged, object: nil)
    }

    var autoFormatOnSave: Bool {
        get { defaults.bool(forKey: "autoFormatOnSave") }
        set { defaults.set(newValue, forKey: "autoFormatOnSave") }
    }

    /// 新規作成した成果物を自動でビューアに開く（E1 / KMD-228）
    var autoOpenNewArtifacts: Bool {
        get {
            if defaults.object(forKey: "autoOpenNewArtifacts") == nil { return true }
            return defaults.bool(forKey: "autoOpenNewArtifacts")
        }
        set { defaults.set(newValue, forKey: "autoOpenNewArtifacts") }
    }

    /// Blocked 検知時に macOS 通知を送る（アクティブでないセッションのみ）。
    var e1NotifyWhenAgentBlocked: Bool {
        get {
            if defaults.object(forKey: "e1NotifyWhenAgentBlocked") == nil {
                return true
            }
            return defaults.bool(forKey: "e1NotifyWhenAgentBlocked")
        }
        set { defaults.set(newValue, forKey: "e1NotifyWhenAgentBlocked") }
    }

    /// E1 terminal + session shell (KMD-231). 未設定時は ON（Re-concept を正とする）。
    var useE1Shell: Bool {
        get {
            if defaults.object(forKey: "useE1Shell") == nil {
                return true
            }
            return defaults.bool(forKey: "useE1Shell")
        }
        set { defaults.set(newValue, forKey: "useE1Shell") }
    }

    // MARK: - Instance API (preferred for testing)

    func saveLastFolder(_ url: URL) {
        defaults.set(url.path, forKey: Self.lastFolderKey)
    }

    func loadLastFolder() -> URL? {
        guard let path = defaults.string(forKey: Self.lastFolderKey) else { return nil }
        return URL(filePath: path)
    }

    func saveLastFile(_ url: URL) {
        defaults.set(url.path, forKey: Self.lastFileKey)
        var recent = defaults.stringArray(forKey: Self.recentFilesKey) ?? []
        recent.removeAll { $0 == url.path }
        recent.insert(url.path, at: 0)
        defaults.set(Array(recent.prefix(Self.maxRecentFiles)), forKey: Self.recentFilesKey)
    }

    func loadLastFile() -> URL? {
        guard let path = defaults.string(forKey: Self.lastFileKey) else { return nil }
        return URL(filePath: path)
    }

    func loadRecentFiles() -> [URL] {
        (defaults.stringArray(forKey: Self.recentFilesKey) ?? [])
            .compactMap { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func clearRecentFiles() {
        defaults.removeObject(forKey: Self.recentFilesKey)
    }

    // MARK: - Workspace folders (multi-root, Security-Scoped Bookmarks)

    func saveWorkspaceFolders(_ urls: [URL]) {
        let bookmarks = urls.compactMap { url -> Data? in
            try? url.bookmarkData(options: .withSecurityScope,
                                  includingResourceValuesForKeys: nil,
                                  relativeTo: nil)
        }
        defaults.set(bookmarks, forKey: Self.workspaceBookmarks)
    }

    func loadWorkspaceFolders() -> [URL] {
        // 新形式（bookmarks）を優先して読み込み
        if let saved = defaults.array(forKey: Self.workspaceBookmarks) as? [Data], !saved.isEmpty {
            return saved.compactMap { data -> URL? in
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: data,
                                         options: .withSecurityScope,
                                         relativeTo: nil,
                                         bookmarkDataIsStale: &stale),
                      FileManager.default.fileExists(atPath: url.path) else { return nil }
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        // レガシーマイグレーション: 旧 lastFolderURL を1件として移行
        if let url = loadLastFolder() {
            saveWorkspaceFolders([url])
            return [url]
        }
        return []
    }

    static func saveWorkspaceFolders(_ urls: [URL]) { shared.saveWorkspaceFolders(urls) }
    static func loadWorkspaceFolders() -> [URL]     { shared.loadWorkspaceFolders() }

    // MARK: - Static shims (backward compatibility)
    // Call sites can migrate to AppState.shared.xxx() over time.

    static func saveLastFolder(_ url: URL) { shared.saveLastFolder(url) }
    static func loadLastFolder() -> URL?   { shared.loadLastFolder() }
    static func saveLastFile(_ url: URL)   { shared.saveLastFile(url) }
    static func loadLastFile() -> URL?     { shared.loadLastFile() }
    static func loadRecentFiles() -> [URL] { shared.loadRecentFiles() }
    static func clearRecentFiles()         { shared.clearRecentFiles() }

    static var useE1Shell: Bool {
        get { shared.useE1Shell }
        set { shared.useE1Shell = newValue }
    }

    static var e1NotifyWhenAgentBlocked: Bool {
        get { shared.e1NotifyWhenAgentBlocked }
        set { shared.e1NotifyWhenAgentBlocked = newValue }
    }

    // MARK: - E1 local sessions

    private struct E1LocalSessionRecord: Codable {
        let id: UUID
        var name: String
        var path: String
    }

    func saveE1LocalSessions(_ sessions: [WorktreeSession], activeID: UUID?) {
        let records = sessions
            .filter(\.isLocalSession)
            .map { E1LocalSessionRecord(id: $0.id, name: $0.name, path: $0.worktreePath.path) }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.e1LocalSessionsKey)
        }
        if let activeID {
            defaults.set(activeID.uuidString, forKey: Self.e1ActiveSessionIDKey)
        } else {
            defaults.removeObject(forKey: Self.e1ActiveSessionIDKey)
        }
    }

    func loadE1LocalSessions() -> ([WorktreeSession], UUID?) {
        guard let data = defaults.data(forKey: Self.e1LocalSessionsKey),
              let records = try? JSONDecoder().decode([E1LocalSessionRecord].self, from: data) else {
            return ([], nil)
        }
        let sessions = records.compactMap { record -> WorktreeSession? in
            let url = URL(fileURLWithPath: record.path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return WorktreeSession.localDirectory(name: record.name, path: url, id: record.id)
        }
        let activeID = defaults.string(forKey: Self.e1ActiveSessionIDKey).flatMap(UUID.init(uuidString:))
        return (sessions, activeID)
    }

    static func saveE1LocalSessions(_ sessions: [WorktreeSession], activeID: UUID?) {
        shared.saveE1LocalSessions(sessions, activeID: activeID)
    }

    static func loadE1LocalSessions() -> ([WorktreeSession], UUID?) {
        shared.loadE1LocalSessions()
    }

    // MARK: - Editor session (open tabs survive dev relaunch)

    func saveEditorSession(tabURLs: [URL], activeURL: URL?) {
        defaults.set(tabURLs.map(\.path), forKey: Self.openTabURLsKey)
        if let activeURL {
            defaults.set(activeURL.path, forKey: Self.activeTabURLKey)
        } else {
            defaults.removeObject(forKey: Self.activeTabURLKey)
        }
    }

    func loadEditorSession() -> (tabURLs: [URL], activeURL: URL?) {
        let tabURLs = (defaults.stringArray(forKey: Self.openTabURLsKey) ?? [])
            .map { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let activeURL = defaults.string(forKey: Self.activeTabURLKey)
            .map { URL(filePath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        return (tabURLs, activeURL)
    }

    static func saveEditorSession(tabURLs: [URL], activeURL: URL?) {
        shared.saveEditorSession(tabURLs: tabURLs, activeURL: activeURL)
    }

    static func loadEditorSession() -> (tabURLs: [URL], activeURL: URL?) {
        shared.loadEditorSession()
    }
}
