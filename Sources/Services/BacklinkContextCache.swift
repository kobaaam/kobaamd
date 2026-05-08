import Foundation
import CryptoKit

final class BacklinkContextCache: @unchecked Sendable {
    enum Verdict: String, Codable, Sendable {
        case yes
        case no
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var storage: [String: Verdict]

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([String: Verdict].self, from: data) {
            self.storage = decoded
        } else {
            self.storage = [:]
        }
    }

    func get(sourceHash: String, targetBasename: String, matchOffset: Int) -> Verdict? {
        lock.lock()
        defer { lock.unlock() }
        return storage[Self.cacheKey(sourceHash: sourceHash, targetBasename: targetBasename, matchOffset: matchOffset)]
    }

    func put(sourceHash: String, targetBasename: String, matchOffset: Int, verdict: Verdict) {
        lock.lock()
        storage[Self.cacheKey(sourceHash: sourceHash, targetBasename: targetBasename, matchOffset: matchOffset)] = verdict
        lock.unlock()
    }

    func save() {
        let snapshot: [String: Verdict]
        lock.lock()
        snapshot = storage
        lock.unlock()

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func hash(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func cacheKey(sourceHash: String, targetBasename: String, matchOffset: Int) -> String {
        "\(sourceHash):\(targetBasename):\(matchOffset)"
    }

    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "kobaamd"
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("backlinks-context-cache.json")
    }
}
