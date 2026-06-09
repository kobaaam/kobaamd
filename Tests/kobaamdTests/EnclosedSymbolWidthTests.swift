import Testing
@testable import kobaamd

@Suite("EnclosedSymbolWidth")
struct EnclosedSymbolWidthTests {
    @Test("circled digits use two columns")
    func circledDigitsAreWide() {
        for scalar in ["①", "②", "③", "⑳"].flatMap({ $0.unicodeScalars }) {
            #expect(EnclosedSymbolWidth.columnCount(for: scalar) == 2)
        }
    }

    @Test("ASCII digits stay one column")
    func asciiDigitsAreNarrow() {
        let scalar = UnicodeScalar(0x31)! // "1"
        #expect(EnclosedSymbolWidth.columnCount(for: scalar) == 1)
    }

    @Test("enclosed CJK ideographs use two columns")
    func enclosedCJKAreWide() {
        let scalar = "㊀".unicodeScalars.first!
        #expect(EnclosedSymbolWidth.columnCount(for: scalar) == 2)
    }
}