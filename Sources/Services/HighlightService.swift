import AppKit

@MainActor final class HighlightService: HighlightServiceProtocol {

    private var theme: ColorTheme { AppState.shared.selectedTheme }

    private let editorFont  = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let boldFont    = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    private let h1Font      = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
    private let h2Font      = NSFont.monospacedSystemFont(ofSize: 17, weight: .bold)
    private let h3Font      = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
    private let codeFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func highlight(_ textStorage: NSTextStorage) {
        guard !textStorage.string.isEmpty else { return }

        let currentTheme = theme

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        let fullRange = NSRange(location: 0, length: textStorage.length)

        // ── Reset to defaults ───────────────────────────────────────
        textStorage.setAttributes([
            .foregroundColor: currentTheme.editorText,
            .font: editorFont,
        ], range: fullRange)

        // ── YAML Front Matter ───────────────────────────────────────
        // Must be at the very start of the document
        applyRegex(#"^---\n[\s\S]*?\n---"#, to: textStorage,
                   options: [.anchorsMatchLines, .dotMatchesLineSeparators],
                   attributes: [.foregroundColor: currentTheme.mutedColor, .font: codeFont])

        // ── ATX Headings (size + colour) ────────────────────────────
        applyRegex(#"^# .+$"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.headingColor, .font: h1Font])
        applyRegex(#"^## .+$"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.headingColor, .font: h2Font])
        applyRegex(#"^#{3,6} .+$"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.linkColor, .font: h3Font])

        // ── Fenced Code Blocks ──────────────────────────────────────
        applyRegex(#"```[\s\S]*?```"#, to: textStorage,
                   options: [.anchorsMatchLines, .dotMatchesLineSeparators],
                   attributes: [.foregroundColor: currentTheme.codeColor, .font: codeFont])

        // ── Indented Code Blocks (4 spaces / tab) ──────────────────
        applyRegex(#"^(    |\t).+"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.codeColor, .font: codeFont])

        // ── Bold + Italic combined (***text***) ─────────────────────
        applyRegex(#"\*{3}[^*\n]+\*{3}"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.headingColor, .font: boldFont, .obliqueness: 0.2])

        // ── Bold (**text** or __text__) ─────────────────────────────
        applyRegex(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.headingColor, .font: boldFont])

        // ── Italic (*text* or _text_) ───────────────────────────────
        applyRegex(#"(?<!\*)\*(?!\*)[^*\n]+\*(?!\*)|(?<!_)_(?!_)[^_\n]+_(?!_)"#,
                   to: textStorage,
                   attributes: [.foregroundColor: currentTheme.headingColor, .obliqueness: 0.2])

        // ── Strikethrough (~~text~~) ────────────────────────────────
        applyRegex(#"~~[^~\n]+~~"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.mutedColor,
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                .strikethroughColor: currentTheme.mutedColor])

        // ── Inline Code (`code`) ────────────────────────────────────
        applyRegex(#"`[^`\n]+`"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.redColor, .font: codeFont])

        // ── Links [label](url) ──────────────────────────────────────
        applyRegex(#"\[([^\]]+)\]\(([^)]+)\)"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.linkColor])
        // Highlight URL part in muted colour
        applyRegex(#"(?<=\]\()([^)]+)(?=\))"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.mutedColor])

        // ── Reference Links [label][ref] ────────────────────────────
        applyRegex(#"\[([^\]]+)\]\[([^\]]*)\]"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.linkColor])

        // ── Images ![alt](url) ──────────────────────────────────────
        applyRegex(#"!\[([^\]]*)\]\([^)]+\)"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.purpleColor])

        // ── Blockquote lines ────────────────────────────────────────
        applyRegex(#"^>+.*$"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.mutedColor, .obliqueness: 0.1])

        // ── Unordered list markers (-, *, +) ────────────────────────
        applyRegex(#"^[ \t]*[-*+] "#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.accentColor])

        // ── Task list checkboxes ─────────────────────────────────────
        applyRegex(#"^[ \t]*[-*+] \[[ xX]\] "#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.accentColor])

        // ── Ordered list markers (1., 2.) ───────────────────────────
        applyRegex(#"^[ \t]*\d+\. "#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.accentColor])

        // ── Horizontal rules ─────────────────────────────────────────
        applyRegex(#"^(---+|===+|\*\*\*+)$"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.mutedColor])

        // ── HTML tags ────────────────────────────────────────────────
        applyRegex(#"</?[a-zA-Z][^>]*>"#, to: textStorage,
                   attributes: [.foregroundColor: currentTheme.mutedColor, .font: codeFont])
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
