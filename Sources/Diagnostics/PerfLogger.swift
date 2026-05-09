import Foundation
import os

/// パフォーマンス計測ロガー。
/// `os.Logger` を使うので `log stream --predicate 'subsystem == "com.kobaamd.app" AND category == "PerfLogger"'`
/// または `--predicate 'category == "PerfLogger"'` で確実にキャプチャできる。
enum PerfLogger {

    private static let logger = Logger(subsystem: "com.kobaamd.app", category: "PerfLogger")
    private static var starts = [String: CFAbsoluteTime]()
    private static let lock = NSLock()

    static func begin(_ name: String) {
        lock.withLock { starts[name] = CFAbsoluteTimeGetCurrent() }
        logger.notice("▶ \(name, privacy: .public)")
    }

    static func end(_ name: String) {
        let elapsed = lock.withLock { () -> Double in
            guard let t = starts[name] else { return -1 }
            starts.removeValue(forKey: name)
            return CFAbsoluteTimeGetCurrent() - t
        }
        guard elapsed >= 0 else { return }
        let ms = elapsed * 1000
        logger.notice("◼ \(name, privacy: .public)  \(ms, format: .fixed(precision: 1)) ms")
    }

    static func event(_ name: String, _ message: String = "") {
        logger.notice("● \(name, privacy: .public) \(message, privacy: .public)")
    }
}
