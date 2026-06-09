import Foundation

// MARK: - CSVTable

/// CSVParser のパース結果。
struct CSVTable: Equatable {
    /// 先頭行をヘッダとして扱う。
    var headers: [String]
    /// ヘッダを除くデータ行。各行の列数が揃わない場合がある。
    var rows: [[String]]
    /// 上限を超えて切り捨てが発生した場合は true。
    var isTruncated: Bool
    /// 全行（ヘッダ含む）の最大列数。描画側が不足セルを空表示する際に参照する。
    var columnCount: Int
}

// MARK: - CSVParser

/// RFC 4180 準拠の CSV パーサ。
/// - 区切り文字: カンマ
/// - クォートフィールドを正しく処理（フィールド内カンマ・改行・エスケープ済みクォート）
/// - 行区切り: LF / CRLF / CR
/// - 巨大ファイル対策: 行上限・列上限で切り捨て
enum CSVParser {
    // MARK: - 上限定数

    /// 取り込む最大行数（ヘッダ行を含む）
    static let maxRows = 10_000
    /// 取り込む最大列数
    static let maxColumns = 512

    // MARK: - パース

    /// `text` を CSV として解析し `CSVTable` を返す。
    /// 空文字列の場合は headers=[], rows=[] を返す。
    static func parse(_ rawText: String) -> CSVTable {
        // Excel 等が出力する CSV は先頭に UTF-8 BOM (U+FEFF) が付くことがある。
        // 先頭の 1 個だけ除去する（フィールド途中の U+FEFF は保持）。
        var text: String = rawText.hasPrefix("\u{FEFF}") ? String(rawText.dropFirst()) : rawText
        // CRLF / CR を LF に正規化して行区切り判定を単純化する（クォート外のみ対象だが、
        // 行区切りはクォート外にしか現れない前提で全体正規化してよい）。
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard !text.isEmpty else {
            return CSVTable(headers: [], rows: [], isTruncated: false, columnCount: 0)
        }

        var allRows: [[String]] = []
        var isTruncated = false

        // 1 文字ずつ走査する状態機械で CSV を分解する
        var currentField = ""
        var currentRow: [String] = []
        var inQuotes = false
        var index = text.startIndex

        func commitField() {
            if currentRow.count < maxColumns {
                currentRow.append(currentField)
            } else {
                // 列上限を超えた分は切り捨て
                isTruncated = true
            }
            currentField = ""
        }

        func commitRow() {
            commitField()
            allRows.append(currentRow)
            currentRow = []
        }

        while index < text.endIndex {
            let ch = text[index]
            let next = text.index(after: index)

            if inQuotes {
                if ch == "\"" {
                    // クォート終了 or エスケープ済みクォート（""）
                    if next < text.endIndex && text[next] == "\"" {
                        // `""` → 1 つの `"` にアンエスケープ
                        currentField.append("\"")
                        index = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    // クォート内の文字はすべてフィールドに含める（改行も同様）
                    currentField.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    // クォート開始
                    inQuotes = true
                case ",":
                    // フィールド区切り
                    commitField()
                case "\n":
                    // LF の行区切り
                    commitRow()
                    // 行数上限チェック
                    if allRows.count >= maxRows {
                        isTruncated = true
                        break
                    }
                default:
                    currentField.append(ch)
                }
            }

            // 行数上限に達したら打ち切る
            if allRows.count >= maxRows {
                isTruncated = true
                break
            }

            index = text.index(after: index)
        }

        // 最終フィールド / 最終行の処理（末尾改行が無い場合も正しく取り込む）
        if !currentField.isEmpty || !currentRow.isEmpty {
            commitRow()
        }

        // 末尾の空行（末尾改行に由来する [] だけの行）を除去
        if let last = allRows.last, last == [] || last == [""] {
            allRows.removeLast()
        }

        // 全行の最大列数を計算
        let maxCols = allRows.map(\.count).max() ?? 0

        // 先頭行をヘッダ、残りをデータ行として分割
        let headers = allRows.first ?? []
        let dataRows = allRows.count > 1 ? Array(allRows.dropFirst()) : []

        return CSVTable(
            headers: headers,
            rows: dataRows,
            isTruncated: isTruncated,
            columnCount: maxCols
        )
    }
}
