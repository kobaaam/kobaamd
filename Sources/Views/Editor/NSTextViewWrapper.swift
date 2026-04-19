import SwiftUI
import AppKit

// MARK: - Editor text area
//
// NSTextView inside NSViewRepresentable renders INVISIBLE text on macOS 26 beta.
// Every approach tried (textColor, typingAttributes, isRichText, appearance,
// drawsBackground, setAttributedString) has failed — the glyph layer loses
// its colour when SwiftUI's appearance injection races with our explicit settings.
//
// CONFIRMED FIX: Use SwiftUI TextEditor (Apple's own NSTextView wrapper).
// It renders text reliably on all supported macOS versions.
//
// Trade-offs until Phase 3:
//   - No inline syntax highlighting
//   - No line number ruler
//   - No scroll-ratio export to preview (previewScrollRatio stays 0)

struct NSTextViewWrapper: View {
    @Binding var text: String
    @Binding var scrollRatio: Double   // reserved — not yet exported

    private static let paperColor = Color(NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1))
    private static let inkColor   = Color(NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1))
    private static let editorFont = Font.system(size: 14, design: .monospaced)

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self._text        = binding
        self._scrollRatio = scrollRatio
    }

    var body: some View {
        TextEditor(text: $text)
            .font(Self.editorFont)
            .foregroundStyle(Self.inkColor)
            .scrollContentBackground(.hidden)
            .background(Self.paperColor)
            .padding(.horizontal, 4)
    }
}
