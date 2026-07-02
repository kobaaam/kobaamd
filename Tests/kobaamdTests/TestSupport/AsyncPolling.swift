import Foundation
import Testing

/// 条件が成立するまで繰り返し確認する。タイムアウト時は Issue.record で失敗させる。
func eventually(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(50),
    message: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async {
    let start = ContinuousClock.now
    // 初回即時評価（既に成立済みなら sleep なしで返る）
    if await condition() { return }
    while ContinuousClock.now - start < timeout {
        try? await Task.sleep(for: pollInterval)
        if await condition() { return }
    }
    let detail = message.map { ": \($0)" } ?? ""
    Issue.record("eventually() timed out after \(timeout)\(detail)", sourceLocation: sourceLocation)
}
