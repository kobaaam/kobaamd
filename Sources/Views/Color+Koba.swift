import SwiftUI

// MARK: - kobaamd design tokens
// Single source of truth for the app's color palette.
// Add new colors here; never hardcode hex values elsewhere.
extension Color {
    // Handoff tokens (tokens.css 準拠)
    static let kobaInk        = Color(hex: "0E0E0E")  // --koba-ink
    static let kobaPaper      = Color(hex: "FDFBF5")  // --koba-paper
    static let kobaAccent     = Color(hex: "FF5B1F")  // --koba-accent
    static let kobaAccentInk  = Color(hex: "B8380B")  // --koba-accent-ink
    static let kobaAccentSoft = Color(hex: "FFE7D8")  // --koba-accent-soft
    static let kobaMute       = Color(hex: "6A6A6A")  // --koba-mute
    static let kobaMute2      = Color(hex: "9A9A9A")  // --koba-mute-2
    static let kobaLine       = Color(hex: "D8D6CF")  // --koba-faint (dividers)

    // Derived surfaces (handoff で明示なし → paper/ink から導出)
    static let kobaSurface = Color(hex: "F5F3ED")  // panel background
    static let kobaSidebar = Color(hex: "F0EEE8")  // sidebar background

    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8)  & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}
