import Testing
@testable import kobaamd

@Suite("CSVParser")
struct CSVParserTests {

    // MARK: - 基本ケース

    @Test("単純な 3×3 CSV がパースできること")
    func simple3x3() {
        let csv = "a,b,c\n1,2,3\n4,5,6"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["a", "b", "c"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["1", "2", "3"])
        #expect(table.rows[1] == ["4", "5", "6"])
        #expect(table.columnCount == 3)
        #expect(!table.isTruncated)
    }

    @Test("クォート無し / クォート有り混在")
    func mixedQuoted() {
        let csv = "name,age,note\nAlice,30,\"hello world\"\nBob,25,plain"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["name", "age", "note"])
        #expect(table.rows[0] == ["Alice", "30", "hello world"])
        #expect(table.rows[1] == ["Bob", "25", "plain"])
    }

    @Test("フィールド内カンマ（\"a,b\"）が正しく扱われること")
    func fieldWithComma() {
        let csv = "a,\"b,c\",d\n1,\"x,y\",3"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["a", "b,c", "d"])
        #expect(table.rows[0] == ["1", "x,y", "3"])
    }

    @Test("フィールド内改行（LF）が正しく保持されること")
    func fieldWithNewline() {
        // "line1\nline2" がひとつのフィールドになる
        let csv = "a,b\n\"line1\nline2\",end"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["a", "b"])
        #expect(table.rows.count == 1)
        #expect(table.rows[0][0] == "line1\nline2")
        #expect(table.rows[0][1] == "end")
    }

    @Test("エスケープ済みクォート（\"\"）が 1 つの \" にアンエスケープされること")
    func escapedQuote() {
        // she said ""hi"" → she said "hi"
        let csv = "msg\n\"she said \"\"hi\"\"\""
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["msg"])
        #expect(table.rows[0][0] == "she said \"hi\"")
    }

    @Test("CRLF 行区切りが正しく扱われること")
    func crlfLineEnding() {
        let csv = "x,y\r\n1,2\r\n3,4"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["x", "y"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["1", "2"])
        #expect(table.rows[1] == ["3", "4"])
    }

    @Test("CR 単独の行区切りが正しく扱われること")
    func crLineEnding() {
        let csv = "x,y\r1,2\r3,4"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["x", "y"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["1", "2"])
    }

    @Test("空フィールド（a,,c）と末尾カンマが正しく扱われること")
    func emptyFields() {
        let csv = "a,,c\n1,,3\n4,5,"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["a", "", "c"])
        #expect(table.rows[0] == ["1", "", "3"])
        // 末尾カンマ → 末尾に空フィールドが生まれる
        #expect(table.rows[1] == ["4", "5", ""])
    }

    @Test("行ごとに列数が違う CSV で落ちないこと")
    func unevenColumns() {
        let csv = "a,b,c\n1,2\n10,20,30,40"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["a", "b", "c"])
        #expect(table.rows[0] == ["1", "2"])
        #expect(table.rows[1] == ["10", "20", "30", "40"])
        // columnCount は全行の最大
        #expect(table.columnCount == 4)
        #expect(!table.isTruncated)
    }

    @Test("空文字列入力は headers=[] / rows=[] を返すこと")
    func emptyInput() {
        let table = CSVParser.parse("")

        #expect(table.headers == [])
        #expect(table.rows == [])
        #expect(table.columnCount == 0)
        #expect(!table.isTruncated)
    }

    @Test("末尾改行あり CSV で余分な空行が発生しないこと")
    func trailingNewline() {
        let csv = "a,b\n1,2\n"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["a", "b"])
        #expect(table.rows.count == 1)
        #expect(table.rows[0] == ["1", "2"])
    }

    @Test("先頭 UTF-8 BOM がヘッダセルに残らないこと")
    func leadingBOMStripped() {
        let csv = "\u{FEFF}name,age\nAlice,30"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["name", "age"])
        // 先頭セルが "\u{FEFF}name" になっていないこと
        #expect(table.headers.first == "name")
    }

    @Test("末尾の複数空セル行（,,）は除去されず保持されること（現状挙動の固定）")
    func trailingAllEmptyCellsRowPreserved() {
        // 末尾行 ",," は ["", "", ""] になり、末尾空行除去の対象外（[] / [""] のみ除去）。
        let csv = "a,b,c\n1,2,3\n,,"
        let table = CSVParser.parse(csv)

        #expect(table.headers == ["a", "b", "c"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["1", "2", "3"])
        #expect(table.rows[1] == ["", "", ""])
    }

    // MARK: - 切り捨てテスト

    @Test("行上限を超えた場合 isTruncated=true になること")
    func truncatedRows() {
        // maxRows + 10 行の CSV を動的生成
        let limit = CSVParser.maxRows
        var lines = ["col1,col2"]
        for i in 0 ..< limit + 10 {
            lines.append("\(i),\(i * 2)")
        }
        let csv = lines.joined(separator: "\n")
        let table = CSVParser.parse(csv)

        #expect(table.isTruncated)
        // ヘッダ + データ行の合計が maxRows を超えないこと
        #expect(table.rows.count <= limit)
    }
}
