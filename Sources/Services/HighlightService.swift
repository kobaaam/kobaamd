import AppKit

final class HighlightService {

    // Fixed sRGB colours — never use dynamic colours (labelColor goes white on macOS 26 dark mode)
    private let inkColor    = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1.0) // #1a1a1a
    private let mutedColor  = NSColor(srgbRed: 0.55,  green: 0.55,  blue: 0.55,  alpha: 1.0)
    private let accentColor = NSColor(srgbRed: 1.0,   green: 0.357, blue: 0.122, alpha: 1.0) // #FF5B1F
    private let blueColor   = NSColor(srgbRed: 0.0,   green: 0.44,  blue: 0.87,  alpha: 1.0)
    private let greenColor  = NSColor(srgbRed: 0.18,  green: 0.56,  blue: 0.27,  alpha: 1.0)
    private let purpleColor = NSColor(srgbRed: 0.55,  green: 0.27,  blue: 0.82,  alpha: 1.0)
    private let redColor    = NSColor(srgbRed: 0.75,  green: 0.20,  blue: 0.17,  alpha: 1.0)

    private let editorFont  = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let boldFont    = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    private let h1Font      = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
    private let h2Font      = NSFont.monospacedSystemFont(ofSize: 17, weight: .bold)
    private let h3Font      = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
    private let codeFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func highlight(_ textStorage: NSTextStorage) {
        guard !textStorage.string.isEmpty else { return }

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        let fullRange = NSRange(location: 0, length: textStorage.length)

        // ── Reset to defaults ───────────────────────────────────────
        textStorage.setAttributes([
            .foregroundColor: inkColor,
            .font: editorFont,
        ], range: fullRange)

        // ── YAML Front Matter ───────────────────────────────────────
        // Must be at the very start of the document
        applyRegex(#"^---\n[\s\S]*?\n---"#, to: textStorage,
                   options: [.anchorsMatchLines, .dotMatchesLineSeparators],
                   attributes: [.foregroundColor: mutedColor, .font: codeFont])

        // ── ATX Headings (size + colour) ────────────────────────────
        applyRegex(#"^# .+$"#, to: textStorage,
                   attributes: [.foregroundColor: inkColor, .font: h1Font])
        applyRegex(#"^## .+$"#, to: textStorage,
                   attributes: [.foregroundColor: inkColor, .font: h2Font])
        applyRegex(#"^#{3,6} .+$"#, to: textStorage,
                   attributes: [.foregroundColor: blueColor, .font: h3Font])

        // ── Fenced Code Blocks ──────────────────────────────────────
        applyRegex(#"```[\s\S]*?```"#, to: textStorage,
                   options: [.anchorsMatchLines, .dotMatchesLineSeparators],
                   attributes: [.foregroundColor: greenColor, .font: codeFont])

        // ── Indented Code Blocks (4 spaces / tab) ──────────────────
        applyRegex(#"^(    |\t).+"#, to: textStorage,
                   attributes: [.foregroundColor: greenColor, .font: codeFont])

        // ── Bold + Italic combined (***text***) ─────────────────────
        applyRegex(#"\*{3}[^*\n]+\*{3}"#, to: textStorage,
                   attributes: [.foregroundColor: inkColor, .font: boldFont, .obliqueness: 0.2])

        // ── Bold (**text** or __text__) ─────────────────────────────
        applyRegex(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, to: textStorage,
                   attributes: [.foregroundColor: inkColor, .font: boldFont])

        // ── Italic (*text* or _text_) ───────────────────────────────
        applyRegex(#"(?<!\*)\*(?!\*)[^*\n]+\*(?!\*)|(?<!_)_(?!_)[^_\n]+_(?!_)"#,
                   to: textStorage,
                   attributes: [.foregroundColor: inkColor, .obliqueness: 0.2])

        // ── Strikethrough (~~text~~) ────────────────────────────────
        applyRegex(#"~~[^~\n]+~~"#, to: textStorage,
                   attributes: [.foregroundColor: mutedColor,
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                .strikethroughColor: mutedColor])

        // ── Inline Code (`code`) ────────────────────────────────────
        applyRegex(#"`[^`\n]+`"#, to: textStorage,
                   attributes: [.foregroundColor: redColor, .font: codeFont])

        // ── Links [label](url) ──────────────────────────────────────
        applyRegex(#"\[([^\]]+)\]\(([^)]+)\)"#, to: textStorage,
                   attributes: [.foregroundColor: blueColor])
        // Highlight URL part in muted colour
        applyRegex(#"(?<=\]\()([^)]+)(?=\))"#, to: textStorage,
                   attributes: [.foregroundColor: mutedColor])

        // ── Reference Links [label][ref] ────────────────────────────
        applyRegex(#"\[([^\]]+)\]\[([^\]]*)\]"#, to: textStorage,
                   attributes: [.foregroundColor: blueColor])

        // ── Images ![alt](url) ──────────────────────────────────────
        applyRegex(#"!\[([^\]]*)\]\([^)]+\)"#, to: textStorage,
                   attributes: [.foregroundColor: purpleColor])

        // ── Blockquote lines ────────────────────────────────────────
        applyRegex(#"^>+.*$"#, to: textStorage,
                   attributes: [.foregroundColor: mutedColor, .obliqueness: 0.1])

        // ── Unordered list markers (-, *, +) ────────────────────────
        applyRegex(#"^[ \t]*[-*+] "#, to: textStorage,
                   attributes: [.foregroundColor: accentColor])

        // ── Task list checkboxes ─────────────────────────────────────
        applyRegex(#"^[ \t]*[-*+] \[[ xX]\] "#, to: textStorage,
                   attributes: [.foregroundColor: accentColor])

        // ── Ordered list markers (1., 2.) ───────────────────────────
        applyRegex(#"^[ \t]*\d+\. "#, to: textStorage,
                   attributes: [.foregroundColor: accentColor])

        // ── Horizontal rules ─────────────────────────────────────────
        applyRegex(#"^(---+|===+|\*\*\*+)$"#, to: textStorage,
                   attributes: [.foregroundColor: mutedColor])

        // ── HTML tags ────────────────────────────────────────────────
        applyRegex(#"</?[a-zA-Z][^>]*>"#, to: textStorage,
                   attributes: [.foregroundColor: mutedColor, .font: codeFont])
    }

    // MARK: - Private

    private func applyRegex(
        _ pattern: String,
        to textStorage: NSTextStorage,
        options: NSRegularExpression.Options = [.anchorsMatchLines],
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let str = textStorage.string
        let range = NSRange(str.startIndex..., in: str)
        for match in regex.matches(in: str, options: [], range: range) {
            textStorage.addAttributes(attributes, range: match.range)
        }
    }
}
