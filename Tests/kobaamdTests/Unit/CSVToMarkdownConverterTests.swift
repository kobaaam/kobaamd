import Testing
@testable import kobaamd

@Suite("CSVToMarkdownConverter")
struct CSVToMarkdownConverterTests {

    // MARK: - ヘルパー

    /// CSVTable を手動で組み立てるヘルパー。columnCount は全行の最大列数。
    private func makeTable(
        headers: [String],
        rows: [[String]],
        isTruncated: Bool = false
    ) -> CSVTable {
        let allRows = [headers] + rows
        let colCount = allRows.map(\.count).max() ?? 0
        return CSVTable(headers: headers, rows: rows, isTruncated: isTruncated, columnCount: colCount)
    }

    // MARK: - テストケース

    @Test("基本変換：ヘッダ＋データ行が GFM テーブルになること")
    func basicConversion() {
        let table = makeTable(
            headers: ["Name", "Age", "City"],
            rows: [["Alice", "30", "Tokyo"], ["Bob", "25", "Osaka"]]
        )
        let result = CSVToMarkdownConverter.convert(table)
        let expected = """
        | Name | Age | City |
        | --- | --- | --- |
        | Alice | 30 | Tokyo |
        | Bob | 25 | Osaka |
        """
        #expect(result == expected)
    }

    @Test("パイプエスケープ：セル内の | が \\| になること")
    func pipeEscape() {
        let table = makeTable(
            headers: ["A|B", "C"],
            rows: [["x|y", "z"]]
        )
        let result = CSVToMarkdownConverter.convert(table)
        #expect(result.contains("A\\|B"))
        #expect(result.contains("x\\|y"))
    }

    @Test("バックスラッシュエスケープ：セル内の \\ が \\\\ になること")
    func backslashEscape() {
        let table = makeTable(
            headers: ["Path"],
            rows: [["C:\\Users\\foo"]]
        )
        let result = CSVToMarkdownConverter.convert(table)
        #expect(result.contains("C:\\\\Users\\\\foo"))
    }

    @Test("空セル：空文字列のセルが正しく処理されること")
    func emptyCells() {
        let table = makeTable(
            headers: ["A", "B", "C"],
            rows: [["", "hello", ""]]
        )
        let result = CSVToMarkdownConverter.convert(table)
        #expect(result.contains("|  | hello |  |"))
    }

    @Test("列不足行：ヘッダより列数が少ない行は空セルで補完されること")
    func unevenRowsFewerColumns() {
        let table = CSVTable(
            headers: ["A", "B", "C"],
            rows: [["only_one"]],
            isTruncated: false,
            columnCount: 3
        )
        let result = CSVToMarkdownConverter.convert(table)
        // データ行は "| only_one |  |  |" になるはず
        #expect(result.contains("| only_one |  |  |"))
    }

    @Test("列超過行：columnCount より多い列は切り捨てられること")
    func unevenRowsMoreColumns() {
        // columnCount=2 に対して 4 列あるデータ行
        let table = CSVTable(
            headers: ["A", "B"],
            rows: [["1", "2", "3", "4"]],
            isTruncated: false,
            columnCount: 2
        )
        let result = CSVToMarkdownConverter.convert(table)
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // データ行は "| 1 | 2 |" のみ（3, 4 は消える）
        #expect(lines.count == 3)
        #expect(lines[2] == "| 1 | 2 |")
    }

    @Test("空テーブル：ヘッダも行もない場合は空文字列を返すこと")
    func emptyTable() {
        let table = CSVTable(headers: [], rows: [], isTruncated: false, columnCount: 0)
        let result = CSVToMarkdownConverter.convert(table)
        #expect(result == "")
    }

    @Test("ヘッダのみ：データ行がない場合はヘッダ行＋セパレータのみ返すこと")
    func headersOnly() {
        let table = makeTable(headers: ["X", "Y"], rows: [])
        let result = CSVToMarkdownConverter.convert(table)
        let expected = """
        | X | Y |
        | --- | --- |
        """
        #expect(result == expected)
    }
}
