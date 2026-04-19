import Foundation

final class AppState {
    private static let defaults = UserDefaults.standard
    private static let lastFolderKey = "lastFolderURL"
    private static let lastFileKey = "lastFileURL"
    private static let recentFilesKey = "recentFiles"
    private static let maxRecentFiles = 10

    static func saveLastFolder(_ url: URL) {
        defaults.set(url.path, forKey: lastFolderKey)
    }

    static func loadLastFolder() -> URL? {
        guard let path = defaults.string(forKey: lastFolderKey) else { return nil }
        return URL(filePath: path)
    }

    static func saveLastFile(_ url: URL) {
        defaults.set(url.path, forKey: lastFileKey)
        var recent = defaults.stringArray(forKey: recentFilesKey) ?? []
        recent.removeAll { $0 == url.path }
        recent.insert(url.path, at: 0)
        defaults.set(Array(recent.prefix(maxRecentFiles)), forKey: recentFilesKey)
    }

    static func loadLastFile() -> URL? {
        guard let path = defaults.string(forKey: lastFileKey) else { return nil }
        return URL(filePath: path)
    }

    static func loadRecentFiles() -> [URL] {
        (defaults.stringArray(forKey: recentFilesKey) ?? [])
            .compactMap { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clearRecentFiles() {
        defaults.removeObject(forKey: recentFilesKey)
    }
}
