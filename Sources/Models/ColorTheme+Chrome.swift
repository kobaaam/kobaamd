import AppKit
import SwiftUI

// MARK: - Shell chrome colors (E1 + app chrome)
//
// Gemini E1 / VS Code dark palette（b8e45c6, ADR-0013）— E1 の標準。
// ターミナルは `editorBackground` と同色 #1e1e1e、前景は `terminalForeground`（#b4b4b4）を使う。
//
// 採用理由（Gemini 起草 + ターミナル実務）:
// - 中立グレーは ANSI 16/256 色の色相ズレが少なく、Claude Code の出力が読みやすい
// - VS Code / iTerm2 / Ghostty 系と同系で長時間作業の目慣れがよい
// - Solarized Dark (#002b36) は紺寄りのキャストが全体に乗り、ターミナルでは赤・緑の判別が鈍りやすい

extension ColorTheme {
    var chromePaper: Color {
        switch self {
        case .light:         return .kobaPaper
        case .dark:          return Color(hex: "1E1E1E")
        case .solarizedDark: return Color(hex: "002B36")
        }
    }

    var chromeSurface: Color {
        switch self {
        case .light:         return .kobaSurface
        case .dark:          return Color(hex: "252526")
        case .solarizedDark: return Color(hex: "073642")
        }
    }

    var chromeSidebar: Color {
        switch self {
        case .light:         return .kobaSidebar
        case .dark:          return Color(hex: "252526")
        case .solarizedDark: return Color(hex: "073642")
        }
    }

    var chromeInk: Color {
        switch self {
        case .light:         return .kobaInk
        case .dark:          return Color(hex: "D4D4D4")
        case .solarizedDark: return Color(hex: "839496")
        }
    }

    var chromeMute: Color {
        switch self {
        case .light:         return .kobaMute
        case .dark:          return Color(hex: "8F8F8F")
        case .solarizedDark: return Color(hex: "657B83")
        }
    }

    var chromeMute2: Color {
        switch self {
        case .light:         return .kobaMute2
        case .dark:          return Color(hex: "6A6A6A")
        case .solarizedDark: return Color(hex: "586E75")
        }
    }

    var chromeLine: Color {
        switch self {
        case .light:         return .kobaLine
        case .dark:          return Color(hex: "4A4A4A")
        case .solarizedDark: return Color(hex: "586E75")
        }
    }

    var chromeSelection: Color {
        switch self {
        case .light:         return .kobaAccentSoft
        case .dark:          return Color(hex: "2A2A2B")
        case .solarizedDark: return Color(hex: "0D3640")
        }
    }

    var chromeSelectedInk: Color {
        switch self {
        case .light:         return .kobaInk
        case .dark, .solarizedDark: return Color.white
        }
    }

    /// タイトルバー / ツールバー用（`chromePaper` より一段明るく、版表示のコントラストを確保）。
    var chromeTitlebar: Color {
        switch self {
        case .light:         return .kobaSurface
        case .dark:          return Color(hex: "2D2D30")
        case .solarizedDark: return Color(hex: "0A3942")
        }
    }

    var chromeTitlebarNSColor: NSColor {
        switch self {
        case .light:
            return NSColor(srgbRed: 0.98, green: 0.98, blue: 0.97, alpha: 1)
        case .dark:
            return NSColor(srgbRed: 0.176, green: 0.176, blue: 0.188, alpha: 1) // #2D2D30
        case .solarizedDark:
            return NSColor(srgbRed: 0.039, green: 0.224, blue: 0.259, alpha: 1) // #0A3942
        }
    }

    var prefersDarkChrome: Bool {
        switch self {
        case .light: return false
        case .dark, .solarizedDark: return true
        }
    }
}