import Testing
@testable import kobaamd
import Foundation

@Suite("BacklinkContextCache")
struct BacklinkContextCacheTests {
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    @Test("Put and get round trip")
    func putAndGetRoundTrip() {
        let fileURL = workspace.url("cache-\(UUID().uuidString).json")
        let cache = BacklinkContextCache(fileURL: fileURL)

        cache.put(sourceHash: "hash-a", targetBasename: "note", matchOffset: 12, verdict: .yes)

        #expect(cache.get(sourceHash: "hash-a", targetBasename: "note", matchOffset: 12) == .yes)
    }

    @Test("Mismatched hash returns nil")
    func mismatchedHashReturnsNil() {
        let fileURL = workspace.url("cache-\(UUID().uuidString).json")
        let cache = BacklinkContextCache(fileURL: fileURL)

        cache.put(sourceHash: "hash-a", targetBasename: "note", matchOffset: 12, verdict: .no)

        #expect(cache.get(sourceHash: "hash-b", targetBasename: "note", matchOffset: 12) == nil)
    }

    @Test("Save and reload preserves data")
    func saveAndReloadPreservesData() {
        let fileURL = workspace.url("cache-\(UUID().uuidString).json")
        let cache = BacklinkContextCache(fileURL: fileURL)

        cache.put(sourceHash: "hash-a", targetBasename: "note", matchOffset: 8, verdict: .yes)
        cache.save()

        let reloaded = BacklinkContextCache(fileURL: fileURL)
        #expect(reloaded.get(sourceHash: "hash-a", targetBasename: "note", matchOffset: 8) == .yes)
    }

    @Test("Malformed file behaves as empty")
    func malformedFileBehavesAsEmpty() throws {
        let fileURL = workspace.url("cache-\(UUID().uuidString).json")
        try Data("not-json".utf8).write(to: fileURL)

        let cache = BacklinkContextCache(fileURL: fileURL)
        #expect(cache.get(sourceHash: "hash-a", targetBasename: "note", matchOffset: 1) == nil)
    }
}