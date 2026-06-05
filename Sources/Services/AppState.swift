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

    var selectedTheme: ColorTheme {
        didSet {
            defaults.set(selectedTheme.rawValue, forKey: Self.selectedThemeKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.selectedThemeKey) ?? ColorTheme.light.rawValue
        self.selectedTheme = ColorTheme(rawValue: raw) ?? .light
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

    var updateCheckInterval: UpdateCheckInterval {
        get {
            let raw = defaults.string(forKey: "updateCheckInterval") ?? UpdateCheckInterval.atLaunch.rawValue
            return UpdateCheckInterval(rawValue: raw) ?? .atLaunch
        }
        set { defaults.set(newValue.rawValue, forKey: "updateCheckInterval") }
    }

    /// E1 terminal + session shell (KMD-231). Default off during Phase A.
    var useE1Shell: Bool {
        get { defaults.bool(forKey: "useE1Shell") }
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
}
