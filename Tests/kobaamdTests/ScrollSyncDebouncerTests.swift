import Testing
@testable import kobaamd

@Suite("Scroll Sync Debouncer")
@MainActor
struct ScrollSyncDebouncerTests {
    @Test("100Hz の連続更新を leading + trailing throttle で 50ms あたり最大1回に抑える")
    func collapsesContinuousBurst() async throws {
        var flushed: [(Double, String)] = []
        let debouncer = ScrollSyncDebouncer(delay: .milliseconds(50)) { ratio, source in
            flushed.append((ratio, source))
        }

        // 100 回の schedule を 10ms 間隔で発火 → 約 1000ms（100Hz 連続スクロール相当）
        for index in 0..<100 {
            debouncer.schedule(ratio: Double(index) / 100, source: "EditorView.onChange")
            try await Task.sleep(for: .milliseconds(10))
        }

        // trailing flush の余韻を待つ
        try await Task.sleep(for: .milliseconds(80))

        // leading-edge 1 回 + 50ms 周期 trailing で 1000ms 中およそ 20 回前後に収束する
        // （タイミング誤差を吸収するため上下に余裕を持たせた範囲で検査）
        #expect(flushed.count >= 2)
        #expect(flushed.count <= 25)
        // 最後に schedule した値が最終 flush に反映されること（trailing が最新値で発火）
        #expect(flushed.last?.0 == 0.99)
        #expect(flushed.last?.1 == "EditorView.onChange")
    }

    @Test("単発の schedule は leading-edge で即座に flush される")
    func leadingEdgeFlushesImmediately() async throws {
        var flushed: [(Double, String)] = []
        let debouncer = ScrollSyncDebouncer(delay: .milliseconds(50)) { ratio, source in
            flushed.append((ratio, source))
        }

        debouncer.schedule(ratio: 0.42, source: "leading-only")

        // sleep なしの直後でも leading flush は同期的に走る
        #expect(flushed.count == 1)
        #expect(flushed.first?.0 == 0.42)
        #expect(flushed.first?.1 == "leading-only")
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
