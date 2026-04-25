import Testing
@testable import kobaamd

@Suite("OutlineViewModel")
@MainActor
struct OutlineViewModelTests {
    let vm = OutlineViewModel()

    @Test("H1のみの抽出が正しいこと")
    func h1OnlyExtraction() async {
        let items = await vm.extractHeadings(from: "# Title")
        #expect(items.count == 1)
        #expect(items[0].level == 1)
        #expect(items[0].text == "Title")
        #expect(items[0].line == 1)
    }

    @Test("H1とH2の混在が正しく抽出されること")
    func h1H2MixedExtraction() async {
        let items = await vm.extractHeadings(from: "# A\n## B")
        #expect(items.count == 2)
        #expect(items[0].level == 1)
        #expect(items[1].level == 2)
    }

    @Test("H1〜H6の全レベルが抽出されること")
    func h1ToH6AllLevels() async {
        let text = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let items = await vm.extractHeadings(from: text)
        #expect(items.count == 6)
    }

    @Test("見出しがない場合はアイテム数0になること")
    func noHeadings() async {
        let items = await vm.extractHeadings(from: "Plain text\nno heading")
        #expect(items.count == 0)
    }

    @Test("空ドキュメントはアイテム数0になること")
    func emptyDocument() async {
        let items = await vm.extractHeadings(from: "")
        #expect(items.count == 0)
    }

    @Test("行番号が正しく計算されること")
    func lineNumberIsCorrect() async {
        let items = await vm.extractHeadings(from: "Para\n\n# Heading")
        #expect(items.count == 1)
        #expect(items[0].line == 3)
    }

    @Test("スペースなし見出しは無視されること（ATX形式のみ有効）")
    func headingWithoutSpaceIsIgnored() async {
        let items = await vm.extractHeadings(from: "#NoSpace")
        #expect(items.count == 0)
    }
}
