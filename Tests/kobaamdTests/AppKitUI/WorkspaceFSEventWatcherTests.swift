import Testing
@testable import kobaamd
import Foundation

// WorkspaceFSEventWatcher のユニットテスト。
//
// テスト戦略:
//   1. debounce ロジック — scheduleReload() を直接呼び、複数回連続呼び出しで最後の1回だけ
//      コールバックが発火することを確認する（v0.4.6 DebounceWorkItem キャンセル回帰ガード）。
//   2. stop() でペンディング debounce がキャンセルされること。
//   3. watch(urls:[]) はハンドラを設定せず即リターンすること。
//   4. 実 FSEvents smoke — TempWorkspace にファイルを書いてコールバックが届くことを確認。
//      FSEvents の配信タイミングは環境依存なため、不安定な場合は .enabled(if: false) で
//      ゲートできるよう設計している。
@Suite("WorkspaceFSEventWatcher")
struct WorkspaceFSEventWatcherTests {

    // MARK: - debounce ロジック

    @Test("scheduleReload を連続で呼んでも最後の1回だけコールバックされる（v0.4.6 回帰ガード）")
    func debounceCoalescesRapidCalls() async throws {
        let watcher = WorkspaceFSEventWatcher()
        let callCount = LockIsolated(0)

        // onChangeHandler を直接設定するため watch を経由せずハンドラを差し込む。
        // watch(urls:onChange:) は止まったストリームを止めてから再生成するため
        // 空パスで watch を呼び、その後ハンドラのみ上書きする（テスト専用パターン）。
        //
        // ただし watch(urls:[]) は guard !paths.isEmpty で即リターンするため
        // onChangeHandler が設定されない。そのため scheduleReload の動作を
        // onChangeHandler なしで呼ぶとハンドラが nil のまま空振りする。
        //
        // 解決策: watch に実パスを渡してストリームを起動したあと、
        // debounce ロジックのみを scheduleReload() から直接テストする。
        // FSEvents ストリームが止まっていてもスケジュールは動く。
        let ws = try TempWorkspace()
        watcher.watch(urls: [ws.root]) {
            callCount.withLock { $0 += 1 }
        }

        // 5回連続 scheduleReload → 各呼び出しが前の WorkItem をキャンセルするため
        // 最終的に fire されるのは最後の1回のみ。
        for _ in 0..<5 {
            watcher.scheduleReload()
        }

        // debounce delay は 0.2s。1.0s 待てば確実に完了している。
        try await Task.sleep(for: .milliseconds(500))
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("stop() は pending debounce をキャンセルする")
    func stopCancelsPendingDebounce() async throws {
        let watcher = WorkspaceFSEventWatcher()
        let callCount = LockIsolated(0)
        let ws = try TempWorkspace()

        watcher.watch(urls: [ws.root]) {
            callCount.withLock { $0 += 1 }
        }
        watcher.scheduleReload()
        // debounce delay (0.2s) が経過する前に stop()
        watcher.stop()
        try await Task.sleep(for: .milliseconds(400))
        #expect(callCount.withLock { $0 } == 0)
    }

    @Test("stop() 後に scheduleReload を呼んでもコールバックされない")
    func stopThenScheduleReloadIsNoop() async throws {
        let watcher = WorkspaceFSEventWatcher()
        let callCount = LockIsolated(0)
        let ws = try TempWorkspace()

        watcher.watch(urls: [ws.root]) {
            callCount.withLock { $0 += 1 }
        }
        watcher.stop()
        // stop() で onChangeHandler が nil になった後に scheduleReload しても
        // DispatchWorkItem 内の self?.onChangeHandler?() が nil を返すだけ。
        watcher.scheduleReload()
        try await Task.sleep(for: .milliseconds(400))
        #expect(callCount.withLock { $0 } == 0)
    }

    @Test("watch(urls:[]) は空配列でハンドラを設定しない")
    func watchEmptyUrlsIsNoop() async throws {
        let watcher = WorkspaceFSEventWatcher()
        let called = LockIsolated(false)
        watcher.watch(urls: []) {
            called.withLock { $0 = true }
        }
        // scheduleReload を呼んでも onChangeHandler が nil のまま
        watcher.scheduleReload()
        try await Task.sleep(for: .milliseconds(400))
        #expect(called.withLock { $0 } == false)
    }

    @Test("watch を2回呼ぶと最初のストリームは停止されて新しいハンドラが有効になる")
    func watchReplacesHandler() async throws {
        let watcher = WorkspaceFSEventWatcher()
        let firstCount = LockIsolated(0)
        let secondCount = LockIsolated(0)
        let ws = try TempWorkspace()

        watcher.watch(urls: [ws.root]) {
            firstCount.withLock { $0 += 1 }
        }
        watcher.watch(urls: [ws.root]) {
            secondCount.withLock { $0 += 1 }
        }
        watcher.scheduleReload()
        try await Task.sleep(for: .milliseconds(400))
        #expect(firstCount.withLock { $0 } == 0)
        #expect(secondCount.withLock { $0 } == 1)
    }

    // MARK: - 実 FSEvents smoke

    @Test("実ファイル書き込みでコールバックが届く（FSEvents smoke）",
          .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil,
                   "CI 環境では FSEvents の配信が不安定なためスキップ"))
    func realFSEventsTriggerCallback() async throws {
        let watcher = WorkspaceFSEventWatcher()
        let ws = try TempWorkspace()
        let triggered = LockIsolated(false)

        watcher.watch(urls: [ws.root]) {
            triggered.withLock { $0 = true }
        }

        // ストリームが起動するまで少し待つ
        try await Task.sleep(for: .milliseconds(100))

        // ファイルを書いてイベントを発生させる
        try ws.write("smoke content", to: "smoke.md")

        // FSEvents latency (0.25s) + debounce (0.2s) + margin = 2.0s
        await eventually(timeout: .seconds(2), message: "FSEvents smoke") {
            triggered.withLock { $0 }
        }
        #expect(triggered.withLock { $0 } == true)
    }

    // MARK: - コンパイル時回帰ガード

    @Test("WorkspaceFSEventWatcher の公開 API が揃っている（コンパイル時回帰ガード）")
    func publicApiExists() {
        let watchRef: (WorkspaceFSEventWatcher) -> ([URL], @escaping @Sendable () -> Void) -> Void
            = WorkspaceFSEventWatcher.watch
        let stopRef: (WorkspaceFSEventWatcher) -> () -> Void = WorkspaceFSEventWatcher.stop
        let scheduleRef: (WorkspaceFSEventWatcher) -> () -> Void = WorkspaceFSEventWatcher.scheduleReload
        _ = watchRef; _ = stopRef; _ = scheduleRef
    }
}

// MARK: - スレッドセーフなカウンタ

/// テスト用のスレッドセーフな値ラッパー。
/// Sendable に準拠するため NSLock でアクセスを直列化する。
private final class LockIsolated<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    @discardableResult
    func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
