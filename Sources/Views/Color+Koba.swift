import SwiftUI

// MARK: - kobaamd design tokens
// Single source of truth for the app's color palette.
// Add new colors here; never hardcode hex values elsewhere.
extension Color {
    static let kobaPaper   = Color(hex: "fdfcf8")  // Editor background (warm white)
    static let kobaSurface = Color(hex: "ffffff")  // Panel surfaces
    static let kobaSidebar = Color(hex: "fafaf7")  // Sidebar background
    static let kobaAccent  = Color(hex: "FF5B1F")  // Brand orange
    static let kobaLine    = Color(hex: "e0ddd8")  // Dividers / borders
    static let kobaMute    = Color(hex: "888888")  // Secondary text
    static let kobaMute2   = Color(hex: "aaaaaa")  // Tertiary text / labels
    static let kobaInk     = Color(hex: "1a1a1a")  // Primary text

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
