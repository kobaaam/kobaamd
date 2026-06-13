import Foundation

/// Herdr 風のセマンティックエージェント状態（Phase A）。
enum E1AgentStatus: String, Equatable, Sendable {
    case blocked
    case working
    case done
    case idle
    case unknown

    var displayName: String {
        switch self {
        case .blocked: "Blocked"
        case .working: "Working"
        case .done: "Done"
        case .idle: "Idle"
        case .unknown: "Unknown"
        }
    }

    /// セッション行のステータスドット色（Herdr 準拠）。
    var indicatorColor: (red: Double, green: Double, blue: Double) {
        switch self {
        case .blocked: (0.92, 0.28, 0.28)
        case .working: (0.95, 0.78, 0.20)
        case .done: (0.28, 0.55, 0.95)
        case .idle: (0.30, 0.78, 0.42)
        case .unknown: (0.55, 0.55, 0.58)
        }
    }

    var showsIndicator: Bool {
        self != .unknown
    }
}

/// ターミナル viewport テキストからエージェント状態を推定する（純関数・テスト可能）。
enum E1AgentStatusParser {
    private static let tailLineLimit = 48
    private static let workingSpinners = CharacterSet(charactersIn: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

    static func parse(viewportText: String) -> E1AgentStatus {
        let normalized = normalize(viewportText)
        guard !normalized.isEmpty else { return .unknown }

        let tail = tailLines(of: normalized, limit: tailLineLimit)
        let joined = tail.joined(separator: "\n")
        let lower = joined.lowercased()

        guard looksLikeCodingAgent(in: lower) else { return .unknown }

        if matchesBlocked(in: tail, lower: lower) { return .blocked }
        if matchesWorking(in: joined, lower: lower) { return .working }
        if matchesDone(in: lower) { return .done }
        if matchesIdle(in: tail, lower: lower) { return .idle }
        return .unknown
    }

    // MARK: - Detection

    private static func looksLikeCodingAgent(in lower: String) -> Bool {
        let markers = [
            "claude code",
            "esc to interrupt",
            "esc to cancel",
            "bypass permissions",
            "ctrl+b",
            "ctrl+b ",
            "codex",
            "opencode",
            "composer",
            "grok build",
            "agent mode",
            "tool use",
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func matchesBlocked(in tail: [String], lower: String) -> Bool {
        let phrases = [
            "do you want",
            "would you like",
            "allow this",
            "yes, allow",
            "yes, and",
            "press enter to",
            "how should i",
            "how would you like",
            "select an option",
            "choose an option",
            "approve",
            "needs permission",
            "requires permission",
            "permission to",
            "proceed?",
            "continue?",
            "y/n",
            " (y/n)",
            "enter to confirm",
            "waiting for your",
            "needs your approval",
            "requires approval",
        ]
        if phrases.contains(where: { lower.contains($0) }) { return true }

        if lower.contains("esc to cancel"), !lower.contains("bypass permissions") {
            return true
        }

        for line in tail.suffix(12) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: #"^\s*[❯>]?\s*\d+[\.\):]"#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static func matchesWorking(in joined: String, lower: String) -> Bool {
        if lower.contains("esc to interrupt") { return true }
        if lower.contains("thinking") || lower.contains("running tool") { return true }
        if joined.unicodeScalars.contains(where: { workingSpinners.contains($0) }) { return true }
        return false
    }

    private static func matchesDone(in lower: String) -> Bool {
        let phrases = [
            "task complete",
            "all done",
            "finished successfully",
            "completed successfully",
            "done —",
            "done -",
        ]
        return phrases.contains { lower.contains($0) }
    }

    private static func matchesIdle(in tail: [String], lower: String) -> Bool {
        guard !lower.contains("esc to interrupt") else { return false }

        if let last = tail.last {
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("❯") || trimmed.hasSuffix(">") { return true }
            if trimmed.range(of: #"[\$%❯>]\s*$"#, options: .regularExpression) != nil {
                return true
            }
        }

        if lower.contains("claude code") && lower.contains("bypass permissions") {
            return true
        }
        return false
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func tailLines(of text: String, limit: Int) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > limit else { return lines }
        return Array(lines.suffix(limit))
    }
}