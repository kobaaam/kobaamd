import Foundation

/// 丸数字・囲み文字など、等幅1セルに押し込むと潰れる記号の幅判定。
/// SwiftTerm の `UnicodeUtil.columnWidth` パッチと同じルールを共有する。
enum EnclosedSymbolWidth {
    static func columnCount(for scalar: UnicodeScalar) -> Int {
        let value = scalar.value
        if isEnclosedAlphanumeric(value) {
            return 2
        }
        return 1
    }

    static func isEnclosedAlphanumeric(_ value: UInt32) -> Bool {
        // Enclosed Alphanumerics: ①②③ … ㊿
        if value >= 0x2460 && value <= 0x24FF { return true }
        // Enclosed CJK Letters and Months: ㊀ … ㋾
        if value >= 0x3200 && value <= 0x32FF { return true }
        return false
    }
}