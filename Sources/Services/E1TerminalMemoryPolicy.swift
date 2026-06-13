import Foundation

/// E1 ターミナルのメモリ・ディスク・CPU 予算。「とにかく軽い」を最優先にする。
enum E1TerminalMemoryPolicy {
    /// Ghostty scrollback cap per surface (RAM). エージェントログはディスク transcript へ逃がす。
    static let scrollbackLimit = "2m"

    /// 同時に PTY を保持する上限。セッション切替では止めず、上限超過時のみ LRU で suspend。
    static let maxActiveTerminals = 6

    /// Per-session transcript cap on disk (~100 MB).
    static let diskTranscriptMaxBytes = 100 * 1024 * 1024

    static let transcriptDirectoryName = ".kobaamd"
    static let transcriptFileName = "transcript.log"

    /// エージェント状態（viewport）のポーリング間隔。
    static let agentStatusPollInterval: TimeInterval = 3.0

    /// transcript（SCREEN 全文読み取り）は N ティックに 1 回だけ。
    static let transcriptEveryNTicks = 10

    static var transcriptPollInterval: TimeInterval {
        agentStatusPollInterval * Double(transcriptEveryNTicks)
    }
}