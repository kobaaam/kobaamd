import Foundation

/// CSV テーブルを GitHub Flavored Markdown (GFM) のテーブル形式に変換するコンバータ。
enum CSVToMarkdownConverter {

    /// `CSVTable` を GFM テーブル文字列に変換する。
    ///
    /// - テーブルが空（ヘッダも行もない）の場合は空文字列を返す。
    /// - セル内の `|` は `\|` に、`\` は `\\` にエスケープする。
    /// - 列数が `table.columnCount` より少ない行は空セルで補完する。
    /// - 列数が `table.columnCount` より多い行は切り捨てる。
    static func convert(_ table: CSVTable) -> String {
        // ヘッダも行もなければ空文字列
        guard !table.headers.isEmpty || !table.rows.isEmpty else {
            return ""
        }

        let colCount = table.columnCount
        // columnCount が 0 になることはほぼないが念のため
        guard colCount > 0 else { return "" }

        var lines: [String] = []

        // ヘッダ行
        let headerCells = paddedAndEscaped(cells: table.headers, columnCount: colCount)
        lines.append(buildRow(cells: headerCells))

        // セパレータ行（GFM 必須）
        let separator = Array(repeating: "---", count: colCount)
        lines.append(buildRow(cells: separator))

        // データ行
        for row in table.rows {
            let dataCells = paddedAndEscaped(cells: row, columnCount: colCount)
            lines.append(buildRow(cells: dataCells))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    /// セル配列を `columnCount` に揃え（不足は補完・超過は切り捨て）、各セルをエスケープする。
    private static func paddedAndEscaped(cells: [String], columnCount: Int) -> [String] {
        var result = cells.prefix(columnCount).map { escape($0) }
        while result.count < columnCount {
            result.append("")
        }
        return result
    }

    /// GFM テーブル行文字列を組み立てる。
    /// 例: `["Name", "Age"]` → `"| Name | Age |"`
    private static func buildRow(cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    /// セル内の特殊文字をエスケープする。
    /// - `\r\n`, `\n`, `\r` → ` `（改行を先にスペースへ正規化。GFM テーブルは改行を含むセルを解釈できない）
    /// - `\` → `\\`（バックスラッシュを先にエスケープして二重処理を防ぐ）
    /// - `|` → `\|`
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
    }
}
