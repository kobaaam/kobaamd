import Testing
@testable import kobaamd
import AppKit

@Suite("ColorTheme terminal colors")
struct ColorThemeTests {
    @Test("dark terminal foreground is softer than editor text")
    func darkTerminalForegroundIsSofter() {
        let editor = rgb8(ColorTheme.dark.editorText)
        let terminal = rgb8(ColorTheme.dark.terminalForeground)
        #expect(terminal.red < editor.red)
        #expect(terminal.green < editor.green)
        #expect(terminal.blue < editor.blue)
    }

    @Test("dark terminal ANSI palette has 16 colors with muted whites")
    func darkTerminalAnsiPalette() {
        let palette = ColorTheme.dark.terminalAnsiPalette
        #expect(palette.count == 16)
        let white = rgb8(palette[7])
        let brightWhite = rgb8(palette[15])
        #expect(white.red == 0xB4 && white.green == 0xB4 && white.blue == 0xB4)
        #expect(brightWhite.red == 0xC8 && brightWhite.green == 0xC8 && brightWhite.blue == 0xC8)
        #expect(brightWhite.red < 0xFF)
    }
}

private struct RGB8 {
    let red: Int
    let green: Int
    let blue: Int
}

private func rgb8(_ color: NSColor) -> RGB8 {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    return RGB8(
        red: Int((r * 255).rounded()),
        green: Int((g * 255).rounded()),
        blue: Int((b * 255).rounded())
    )
}