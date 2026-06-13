import Foundation
import Testing
@testable import kobaamd

@Suite("E1 terminal transcript")
struct E1TerminalTranscriptTests {
    @Test("disk transcript cap is 100 MB")
    func diskCapIs100MB() {
        #expect(E1TerminalMemoryPolicy.diskTranscriptMaxBytes == 100 * 1024 * 1024)
    }

    @Test("delta append extends previous snapshot")
    func deltaExtendsPrevious() {
        let previousText = "line1\nline2"
        let previous = snapshot(for: previousText)
        let result = E1TerminalTranscriptDelta.appendDelta(
            previous: previous,
            current: "line1\nline2\nline3"
        )
        #expect(result?.delta == "\nline3")
    }

    @Test("delta handles scrollback roll with suffix overlap")
    func deltaHandlesScrollbackRoll() {
        let previous = snapshot(for: "old1\nold2\nold3\nvisible")
        let result = E1TerminalTranscriptDelta.appendDelta(
            previous: previous,
            current: "old2\nold3\nvisible\nnew"
        )
        #expect(result?.delta == "\nnew")
    }

    @Test("delta overlap probe stays bounded for large screens")
    func deltaOverlapProbeIsBounded() {
        let previous = snapshot(for: String(repeating: "a", count: 200_000))
        let start = CFAbsoluteTimeGetCurrent()
        _ = E1TerminalTranscriptDelta.appendDelta(
            previous: previous,
            current: String(repeating: "b", count: 200_000)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        #expect(elapsed < 0.5)
    }

    private func snapshot(for text: String) -> E1TerminalScreenSnapshot {
        let utf8 = Array(text.utf8)
        return E1TerminalScreenSnapshot(
            utf8Count: utf8.count,
            tailUTF8: Data(utf8.suffix(min(utf8.count, E1TerminalTranscriptDelta.snapshotTailMaxBytes)))
        )
    }

    @Test("trim keeps tail within max bytes")
    func trimKeepsTail() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-transcript-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("transcript.log")
        let payload = String(repeating: "x", count: 1200)
        try payload.data(using: .utf8)!.write(to: url)

        try E1TerminalTranscriptStore.trimToMaxBytes(at: url, maxBytes: 500)

        let trimmed = try String(contentsOf: url, encoding: .utf8)
        #expect(trimmed.count <= 500)
        #expect(trimmed.hasSuffix("x"))
    }

    @Test("appendDelta writes under worktree .kobaamd")
    func appendWritesTranscriptFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-transcript-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try E1TerminalTranscriptStore.appendDelta(
            previousSnapshot: nil,
            currentScreen: "hello\nworld",
            to: directory
        )

        let url = E1TerminalTranscriptStore.transcriptURL(for: directory)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "hello\nworld")
    }
}