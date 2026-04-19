import AppKit

final class HighlightService {
    func highlight(_ textStorage: NSTextStorage) {
        guard !textStorage.string.isEmpty else { return }

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Reset to defaults
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        textStorage.addAttribute(.font, value: editorFont, range: fullRange)

        // ATX Headings
        applyRegex(#"^#{1,6}\s.*$"#, to: textStorage,
                   attributes: [.foregroundColor: NSColor.systemBlue, .font: boldFont])

        // Code blocks (before inline code to avoid overlap)
        applyRegex(#"```[\s\S]*?```"#, to: textStorage,
                   options: [.anchorsMatchLines, .dotMatchesLineSeparators],
                   attributes: [.foregroundColor: NSColor.systemGreen, .font: codeFont])

        // Bold
        applyRegex(#"(\*\*[^*\n]+\*\*|__[^_\n]+__)"#, to: textStorage,
                   attributes: [.foregroundColor: NSColor.labelColor, .font: boldFont])

        // Italic
        applyRegex(#"(\*[^*\n]+\*|_[^_\n]+_)"#, to: textStorage,
                   attributes: [.foregroundColor: NSColor.labelColor, .obliqueness: 0.2])

        // Inline code
        applyRegex(#"`[^`\n]+`"#, to: textStorage,
                   attributes: [.foregroundColor: NSColor.systemGreen, .font: codeFont])

        // Links
        applyRegex(#"\[([^\]]+)\]\([^)]+\)"#, to: textStorage,
                   attributes: [.foregroundColor: NSColor.systemBlue])

        // Blockquote
        applyRegex(#"^>.*$"#, to: textStorage,
                   attributes: [.foregroundColor: NSColor.systemGray])

        // Horizontal rule
        applyRegex(#"^(---+|===+|\*\*\*+)$"#, to: textStorage,
                   attributes: [.foregroundColor: NSColor.systemGray])
    }

    private func applyRegex(
        _ pattern: String,
        to textStorage: NSTextStorage,
        options: NSRegularExpression.Options = [.anchorsMatchLines],
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(location: 0, length: textStorage.length)
        for match in regex.matches(in: textStorage.string, options: [], range: range) {
            textStorage.addAttributes(attributes, range: match.range)
        }
    }
}
