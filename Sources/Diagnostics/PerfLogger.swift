import Foundation

/// パフォーマンス計測ロガー（コンソール出力）。
/// begin/end の name を一致させて使う。同名の計測が重複しないこと。
enum PerfLogger {

    private static var starts = [String: CFAbsoluteTime]()
    private static let lock = NSLock()

    static func begin(_ name: String) {
        lock.withLock { starts[name] = CFAbsoluteTimeGetCurrent() }
        NSLog("[PERF] ▶ \(name)")
    }

    static func end(_ name: String) {
        let elapsed = lock.withLock { () -> Double in
            guard let t = starts[name] else { return -1 }
            starts.removeValue(forKey: name)
            return CFAbsoluteTimeGetCurrent() - t
        }
        guard elapsed >= 0 else { return }
        NSLog(String(format: "[PERF] ◼ \(name)  %.1f ms", elapsed * 1000))
    }

    static func event(_ name: String, _ message: String = "") {
        NSLog("[PERF] ● \(name) \(message)")
    }
}
