import Foundation
import Testing

/// 条件が成立するまで繰り返し確認する。タイムアウト時は Issue.record で失敗させる。
func eventually(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(50),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if await condition() { return }
        try? await Task.sleep(for: pollInterval)
    }
    Issue.record("eventually() timed out after \(timeout)", sourceLocation: sourceLocation)
}
