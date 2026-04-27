import Testing
@testable import kobaamd

@Suite("MarkdownFormatterService")
struct MarkdownFormatterServiceTests {
    private let service = MarkdownFormatterService()

    @Test("末尾スペースが除去されること")
    func testRemovesTrailingSpaces() {
        let input = "alpha   \nbeta\t\t"
        let result = service.format(input)

        #expect(result.result == "alpha\nbeta")
    }

    @Test("3行以上の空行が2行に圧縮されること")
    func testCompressesBlankLines() {
        let input = "a\n\n\n\nb"
        let result = service.format(input)

        #expect(result.result == "a\n\n\nb")
    }

    @Test("コードブロック内部は保持されること")
    func testCodeBlockPreserved() {
        let input = "before\n\n~~~swift\nlet value = 1  \n\n\nprint(value)\n~~~"
        let result = service.format(input)
        let expected = "before\n\n```swift\nlet value = 1  \n\n\nprint(value)\n```"

        #expect(result.result == expected)
    }

    @Test("見出し前後に空行が追加されること")
    func testHeadingSpacing() {
        let input = "intro\n## Section\nbody"
        let result = service.format(input)

        #expect(result.result == "intro\n\n## Section\n\nbody")
    }

    @Test("変更がある場合は changeCount が 0 より大きいこと")
    func testChangeCountIsNonZero() {
        let input = "alpha   "
        let result = service.format(input)

        #expect(result.changeCount > 0)
    }
}
