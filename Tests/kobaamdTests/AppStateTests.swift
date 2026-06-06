import Testing
@testable import kobaamd
import Foundation
import Observation

// Uses injected UserDefaults (suiteName) for proper test isolation.
// No shared state between tests — .serialized is no longer required.
@Suite("AppState")
struct AppStateTests {
    let state: AppState
    let defaults: UserDefaults

    init() throws {
        let suiteName = "kobaamd.test.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        state = AppState(defaults: defaults)
    }

    // MARK: - Last folder

    @Test("Save and load last folder round trips")
    func saveAndLoadLastFolder() {
        let url = URL(filePath: "/tmp/testfolder")
        state.saveLastFolder(url)
        #expect(state.loadLastFolder()?.path == url.path)
    }

    @Test("loadLastFolder returns nil when absent")
    func loadLastFolderNilWhenAbsent() {
        #expect(state.loadLastFolder() == nil)
    }

    // MARK: - Last file

    @Test("Save and load last file round trips")
    func saveAndLoadLastFile() {
        let url = URL(filePath: "/tmp/note.md")
        state.saveLastFile(url)
        #expect(state.loadLastFile()?.path == url.path)
    }

    @Test("loadLastFile returns nil when absent")
    func loadLastFileNilWhenAbsent() {
        #expect(state.loadLastFile() == nil)
    }

    @Test("Second saveLastFile overwrites the first")
    func saveLastFileOverwrites() {
        state.saveLastFile(URL(filePath: "/tmp/a.md"))
        let b = URL(filePath: "/tmp/b.md")
        state.saveLastFile(b)
        #expect(state.loadLastFile()?.path == b.path)
    }

    // MARK: - Recent files

    @Test("Most recently saved file is first in recents")
    func recentFilesAreMostRecentFirst() {
        let a = URL(filePath: "/tmp/a.md")
        let b = URL(filePath: "/tmp/b.md")
        state.saveLastFile(a)
        state.saveLastFile(b)
        let paths = defaults.stringArray(forKey: "recentFiles") ?? []
        #expect(paths.first == b.path)
    }

    @Test("Same file saved twice appears only once in recents")
    func recentFilesDeduplicates() {
        let url = URL(filePath: "/tmp/note.md")
        state.saveLastFile(url)
        state.saveLastFile(url)
        let paths = defaults.stringArray(forKey: "recentFiles") ?? []
        #expect(paths.filter { $0 == url.path }.count == 1)
    }

    @Test("Re-opened file moves to front of recents")
    func recentFilesMovesDuplicateToFront() {
        let a = URL(filePath: "/tmp/a.md")
        let b = URL(filePath: "/tmp/b.md")
        state.saveLastFile(a)
        state.saveLastFile(b)
        state.saveLastFile(a)
        let paths = defaults.stringArray(forKey: "recentFiles") ?? []
        #expect(paths.first == a.path)
    }

    @Test("Recent files are capped at 10 entries")
    func recentFilesCapAt10() {
        for i in 0..<15 {
            state.saveLastFile(URL(filePath: "/tmp/file\(i).md"))
        }
        let paths = defaults.stringArray(forKey: "recentFiles") ?? []
        #expect(paths.count <= 10)
    }

    // MARK: - clearRecentFiles

    @Test("clearRecentFiles removes all entries")
    func clearRecentFilesRemovesAll() {
        state.saveLastFile(URL(filePath: "/tmp/a.md"))
        state.saveLastFile(URL(filePath: "/tmp/b.md"))
        state.clearRecentFiles()
        let paths = defaults.stringArray(forKey: "recentFiles") ?? []
        #expect(paths.isEmpty)
    }

    // MARK: - E1 shell flag

    @Test("useE1Shell defaults to false and persists")
    func useE1ShellPersists() {
        #expect(state.useE1Shell == false)
        state.useE1Shell = true
        #expect(defaults.bool(forKey: "useE1Shell") == true)
        #expect(state.useE1Shell == true)
        state.useE1Shell = false
        #expect(state.useE1Shell == false)
    }

    // MARK: - Color theme

    @Test("selectedTheme assignment persists raw value to UserDefaults")
    func selectedThemePersists() {
        state.selectedTheme = .dark
        #expect(defaults.string(forKey: "selectedColorTheme") == "dark")
        state.selectedTheme = .solarizedDark
        #expect(defaults.string(forKey: "selectedColorTheme") == "solarizedDark")
    }

    @Test("selectedTheme initializes from UserDefaults raw value")
    func selectedThemeReadsFromDefaultsOnInit() throws {
        let suiteName = "kobaamd.test.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.set("dark", forKey: "selectedColorTheme")
        let preset = AppState(defaults: suite)
        #expect(preset.selectedTheme == .dark)
    }

    @Test("selectedTheme falls back to .light on invalid raw value")
    func selectedThemeFallbackOnInvalid() throws {
        let suiteName = "kobaamd.test.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.set("not-a-real-theme", forKey: "selectedColorTheme")
        let preset = AppState(defaults: suite)
        #expect(preset.selectedTheme == .light)
    }

    @Test("selectedTheme assignment fires @Observable change notification")
    func selectedThemeFiresObservation() async {
        var notified = false
        withObservationTracking {
            _ = state.selectedTheme
        } onChange: {
            notified = true
        }
        state.selectedTheme = .dark
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(notified == true)
    }

    // MARK: - loadRecentFiles filtering

    // MARK: - Editor session

    @Test("Editor session round-trips tab URLs and active tab")
    func editorSessionRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.md")
        let b = dir.appendingPathComponent("b.md")
        try "# A".write(to: a, atomically: true, encoding: .utf8)
        try "# B".write(to: b, atomically: true, encoding: .utf8)

        state.saveEditorSession(tabURLs: [a, b], activeURL: b)
        let loaded = state.loadEditorSession()
        #expect(loaded.tabURLs.map(\.path) == [a.path, b.path])
        #expect(loaded.activeURL?.path == b.path)
    }

    @Test("loadEditorSession drops missing tab files")
    func loadEditorSessionSkipsMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let live = dir.appendingPathComponent("live.md")
        try "# live".write(to: live, atomically: true, encoding: .utf8)
        let gone = dir.appendingPathComponent("gone.md")

        state.saveEditorSession(tabURLs: [live, gone], activeURL: live)
        let loaded = state.loadEditorSession()
        #expect(loaded.tabURLs == [live])
        #expect(loaded.activeURL == live)
    }

    @Test("loadRecentFiles skips missing files")
    func loadRecentFilesSkipsMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = dir.appendingPathComponent("note.md")
        try "# live".write(to: existing, atomically: true, encoding: .utf8)
        let missing = dir.appendingPathComponent("gone.md")   // file never created

        state.saveLastFile(existing)
        state.saveLastFile(missing)

        let results = state.loadRecentFiles()
        #expect(results.contains(existing))
        #expect(!results.contains(missing))
    }
}
