import Testing
@testable import kobaamd
import Foundation

// NOTE: AppState uses UserDefaults.standard directly.
// .serialized prevents parallel execution that would cause UserDefaults race conditions.
// Planned refactor: inject UserDefaults for proper test isolation.
@Suite("AppState", .serialized)
struct AppStateTests {
    let defaults = UserDefaults.standard
    let folderKey = "lastFolderURL"
    let fileKey = "lastFileURL"
    let recentKey = "recentFiles"

    init() {
        cleanKeys()
    }

    private func cleanKeys() {
        defaults.removeObject(forKey: folderKey)
        defaults.removeObject(forKey: fileKey)
        defaults.removeObject(forKey: recentKey)
    }

    // MARK: - Last folder

    @Test("Save and load last folder round trips")
    func saveAndLoadLastFolder() {
        let url = URL(filePath: "/tmp/testfolder")
        AppState.saveLastFolder(url)
        #expect(AppState.loadLastFolder()?.path == url.path)
        cleanKeys()
    }

    @Test("loadLastFolder returns nil when absent")
    func loadLastFolderNilWhenAbsent() {
        #expect(AppState.loadLastFolder() == nil)
    }

    // MARK: - Last file

    @Test("Save and load last file round trips")
    func saveAndLoadLastFile() {
        let url = URL(filePath: "/tmp/note.md")
        AppState.saveLastFile(url)
        #expect(AppState.loadLastFile()?.path == url.path)
        cleanKeys()
    }

    @Test("loadLastFile returns nil when absent")
    func loadLastFileNilWhenAbsent() {
        #expect(AppState.loadLastFile() == nil)
    }

    @Test("Second saveLastFile overwrites the first")
    func saveLastFileOverwrites() {
        let a = URL(filePath: "/tmp/a.md")
        let b = URL(filePath: "/tmp/b.md")
        AppState.saveLastFile(a)
        AppState.saveLastFile(b)
        #expect(AppState.loadLastFile()?.path == b.path)
        cleanKeys()
    }

    // MARK: - Recent files

    @Test("Most recently saved file is first in recents")
    func recentFilesAreMostRecentFirst() {
        let a = URL(filePath: "/tmp/a.md")
        let b = URL(filePath: "/tmp/b.md")
        AppState.saveLastFile(a)
        AppState.saveLastFile(b)
        let paths = defaults.stringArray(forKey: recentKey) ?? []
        #expect(paths.first == b.path)
        cleanKeys()
    }

    @Test("Same file saved twice appears only once in recents")
    func recentFilesDeduplicates() {
        let url = URL(filePath: "/tmp/note.md")
        AppState.saveLastFile(url)
        AppState.saveLastFile(url)
        let paths = defaults.stringArray(forKey: recentKey) ?? []
        #expect(paths.filter { $0 == url.path }.count == 1)
        cleanKeys()
    }

    @Test("Re-opened file moves to front of recents")
    func recentFilesMovesDuplicateToFront() {
        let a = URL(filePath: "/tmp/a.md")
        let b = URL(filePath: "/tmp/b.md")
        AppState.saveLastFile(a)
        AppState.saveLastFile(b)
        AppState.saveLastFile(a)
        let paths = defaults.stringArray(forKey: recentKey) ?? []
        #expect(paths.first == a.path)
        cleanKeys()
    }

    @Test("Recent files are capped at 10 entries")
    func recentFilesCapAt10() {
        for i in 0..<15 {
            AppState.saveLastFile(URL(filePath: "/tmp/file\(i).md"))
        }
        let paths = defaults.stringArray(forKey: recentKey) ?? []
        #expect(paths.count <= 10)
        cleanKeys()
    }

    // MARK: - clearRecentFiles

    @Test("clearRecentFiles removes all entries")
    func clearRecentFilesRemovesAll() {
        AppState.saveLastFile(URL(filePath: "/tmp/a.md"))
        AppState.saveLastFile(URL(filePath: "/tmp/b.md"))
        AppState.clearRecentFiles()
        let paths = defaults.stringArray(forKey: recentKey) ?? []
        #expect(paths.isEmpty)
    }
}
