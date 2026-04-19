import SwiftUI
import AppKit

// MARK: - Editor text area
//
// Previous implementation used NSViewRepresentable wrapping NSTextView.
// On macOS 26 beta, text was persistently invisible regardless of textColor,
// typingAttributes, isRichText, appearance override, or setAttributedString
// approaches — a known fragility in the SwiftUI↔AppKit bridge on that OS.
//
// This version uses SwiftUI's built-in TextEditor (Apple's own NSTextView
// wrapper) which renders reliably on all supported macOS versions.
// Trade-offs for now: no inline syntax highlighting, no ruler line numbers,
// no scroll-ratio export. These are tracked for Phase 3.

struct NSTextViewWrapper: View {
    @Binding var text: String
    @Binding var scrollRatio: Double

    private static let paperColor = Color(NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1))
    private static let inkColor   = Color(NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1))
    private static let editorFont = Font.system(size: 14, design: .monospaced)

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self._text      = binding
        self._scrollRatio = scrollRatio
    }

    var body: some View {
        TextEditor(text: $text)
            .font(Self.editorFont)
            .foregroundStyle(Self.inkColor)
            .scrollContentBackground(.hidden)
            .background(Self.paperColor)
            .padding(.horizontal, 4)   // slight left indent to align with ruler area
    }
}
