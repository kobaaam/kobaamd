import Testing
@testable import kobaamd
import AppKit

@Suite("E1TerminalTypography")
struct E1TerminalTypographyTests {
    @Test("monospaceFont uses requested point size")
    func fontSizeMatchesRequest() {
        let font = E1TerminalTypography.monospaceFont(size: 15)
        #expect(font.pointSize == 15)
        #expect(font.isFixedPitch)
    }

    @Test("monospaceFont prefers SF Mono or Menlo")
    func fontUsesKnownMonospaceFamily() {
        let font = E1TerminalTypography.monospaceFont(size: 14)
        let name = font.fontName.lowercased()
        #expect(name.contains("sfmono") || name.contains("menlo") || name.contains("monaco"))
    }
}