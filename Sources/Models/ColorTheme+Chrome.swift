import SwiftUI

// MARK: - Shell chrome colors (E1 + app chrome)
// Gemini E1 dark palette: main #1e1e1e, panels #252526, text #d4d4d4

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
}