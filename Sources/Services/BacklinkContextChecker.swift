import Foundation

protocol BacklinkContextCheckerProtocol: Sendable {
    func judge(
        sourceContent: String,
        snippet: String,
        targetBasename: String
    ) async -> BacklinkContextCache.Verdict?
}

/// Re-concept では外部 API を使わないため、文脈判定は常に nil（未リンク候補を出さない）。
struct NoOpBacklinkContextChecker: BacklinkContextCheckerProtocol {
    func judge(
        sourceContent: String,
        snippet: String,
        targetBasename: String
    ) async -> BacklinkContextCache.Verdict? {
        nil
    }
}

typealias BacklinkContextChecker = NoOpBacklinkContextChecker