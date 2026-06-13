import Foundation

/// セッション作業ディレクトリ配下に PTY 出力 transcript を追記し、容量上限でローテーションする。
enum E1TerminalTranscriptStore {
    static func transcriptURL(for worktree: URL) -> URL {
        worktree
            .appendingPathComponent(E1TerminalMemoryPolicy.transcriptDirectoryName, isDirectory: true)
            .appendingPathComponent(E1TerminalMemoryPolicy.transcriptFileName)
    }

    /// 直前スナップショットと現行スクリーン全文の差分を追記する。
    static func appendDelta(
        previousSnapshot: E1TerminalScreenSnapshot?,
        currentScreen: String,
        to worktree: URL
    ) throws -> E1TerminalScreenSnapshot? {
        guard let result = E1TerminalTranscriptDelta.appendDelta(
            previous: previousSnapshot,
            current: currentScreen
        ) else {
            return previousSnapshot
        }

        let (delta, nextSnapshot) = result
        if !delta.isEmpty {
            try write(delta, to: worktree)
        }
        return nextSnapshot
    }

    private static func write(_ delta: String, to worktree: URL) throws {
        let url = transcriptURL(for: worktree)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = delta.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }

        try trimToMaxBytes(at: url, maxBytes: E1TerminalMemoryPolicy.diskTranscriptMaxBytes)
    }

    static func trimToMaxBytes(at url: URL, maxBytes: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? Int, size > maxBytes else { return }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let offset = UInt64(size - maxBytes)
        try handle.seek(toOffset: offset)
        var tail = handle.readDataToEndOfFile()

        if let firstNewline = tail.firstIndex(of: 0x0A) {
            tail = Data(tail.suffix(from: tail.index(after: firstNewline)))
        }

        try tail.write(to: url, options: .atomic)
    }
}

/// SCREEN 読み取り結果の軽量メタデータ（全文は保持しない）。
struct E1TerminalScreenSnapshot: Equatable {
    let utf8Count: Int
    let tailUTF8: Data
}

/// Ghostty SCREEN スナップショット間の追記差分（scrollback ロールオーバー耐性）。
enum E1TerminalTranscriptDelta {
    /// scrollback ロール時の接続点探索上限（バイト）。
    static let overlapProbeMaxBytes = 16 * 1024
    /// 接続点検証用に保持する末尾バイト数。
    static let snapshotTailMaxBytes = 32 * 1024

    static func appendDelta(
        previous: E1TerminalScreenSnapshot?,
        current: String
    ) -> (delta: String, next: E1TerminalScreenSnapshot)? {
        let currentUTF8 = Array(current.utf8)
        guard !currentUTF8.isEmpty else { return nil }

        let nextSnapshot = makeSnapshot(from: currentUTF8)
        guard let previous else {
            return (current, nextSnapshot)
        }

        if previous.utf8Count == currentUTF8.count,
           previous.tailUTF8 == nextSnapshot.tailUTF8 {
            return nil
        }

        if currentUTF8.count > previous.utf8Count,
           regionsMatch(
               Array(currentUTF8.prefix(previous.utf8Count).suffix(previous.tailUTF8.count)),
               Array(previous.tailUTF8)
           ) {
            let deltaBytes = currentUTF8.dropFirst(previous.utf8Count)
            let delta = String(decoding: deltaBytes, as: UTF8.self)
            return (delta, nextSnapshot)
        }

        let prevProbe = Array(previous.tailUTF8.suffix(overlapProbeMaxBytes))
        let limit = min(prevProbe.count, currentUTF8.count)
        for overlap in stride(from: limit, through: 1, by: -1) {
            if regionsMatch(Array(currentUTF8.prefix(overlap)), Array(prevProbe.suffix(overlap))) {
                let delta = String(decoding: currentUTF8.dropFirst(overlap), as: UTF8.self)
                return (delta, nextSnapshot)
            }
        }

        return (current, nextSnapshot)
    }

    private static func makeSnapshot(from utf8: [UInt8]) -> E1TerminalScreenSnapshot {
        E1TerminalScreenSnapshot(
            utf8Count: utf8.count,
            tailUTF8: Data(utf8.suffix(min(utf8.count, snapshotTailMaxBytes)))
        )
    }

    private static func regionsMatch(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.elementsEqual(rhs)
    }
}