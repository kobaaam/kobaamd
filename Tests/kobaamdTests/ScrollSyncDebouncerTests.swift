import Testing
@testable import kobaamd

@Suite("Scroll Sync Debouncer")
@MainActor
struct ScrollSyncDebouncerTests {
    @Test("100Hz の連続更新を trailing-only で 20/sec 以下に抑える")
    func collapsesContinuousBurst() async throws {
        var flushed: [(Double, String)] = []
        let debouncer = ScrollSyncDebouncer(delay: .milliseconds(50)) { ratio, source in
            flushed.append((ratio, source))
        }

        for index in 0..<100 {
            debouncer.schedule(ratio: Double(index) / 100, source: "EditorView.onChange")
            try await Task.sleep(for: .milliseconds(10))
        }

        try await Task.sleep(for: .milliseconds(80))

        #expect(flushed.count <= 20)
        #expect(flushed.count == 1)
        #expect(flushed.last?.1 == "EditorView.onChange")
    }

    @Test("間隔が debounce より長ければ個別に flush される")
    func flushesSeparatedUpdates() async throws {
        var flushed: [(Double, String)] = []
        let debouncer = ScrollSyncDebouncer(delay: .milliseconds(50)) { ratio, source in
            flushed.append((ratio, source))
        }

        debouncer.schedule(ratio: 0.2, source: "first")
        try await Task.sleep(for: .milliseconds(80))
        debouncer.schedule(ratio: 0.7, source: "second")
        try await Task.sleep(for: .milliseconds(80))

        #expect(flushed.count == 2)
        #expect(flushed.map(\.0) == [0.2, 0.7])
        #expect(flushed.map(\.1) == ["first", "second"])
    }
}
