import SwiftUI

// MARK: - E1 center pane placeholder (KMD-225)

struct E1TerminalPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundStyle(Color.kobaMute)
            Text("Terminal (PTY)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.kobaInk)
            Text("KMD-225")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.kobaMute)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaPaper)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Terminal placeholder, KMD-225")
    }
}