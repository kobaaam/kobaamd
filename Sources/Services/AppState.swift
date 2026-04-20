import Foundation

final class AppState {
    // Inject UserDefaults for testability; defaults to .standard in production.
    let defaults: UserDefaults

    static let shared = AppState()

    private static let lastFolderKey  = "lastFolderURL"
    private static let lastFileKey    = "lastFileURL"
    private static let recentFilesKey = "recentFiles"
    private static let maxRecentFiles = 10

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    // MARK: - Static shims (backward compatibility)
    // Call sites can migrate to AppState.shared.xxx() over time.

    static func saveLastFolder(_ url: URL) { shared.saveLastFolder(url) }
    static func loadLastFolder() -> URL?   { shared.loadLastFolder() }
    static func saveLastFile(_ url: URL)   { shared.saveLastFile(url) }
    static func loadLastFile() -> URL?     { shared.loadLastFile() }
    static func loadRecentFiles() -> [URL] { shared.loadRecentFiles() }
    static func clearRecentFiles()         { shared.clearRecentFiles() }
}
