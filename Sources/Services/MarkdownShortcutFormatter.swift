import Foundation

enum MarkdownShortcutKind {
    case bold
    case italic
    case link
}

struct MarkdownShortcutEdit {
    let replacementRange: NSRange
    let replacementText: String
    let selectedRange: NSRange
}

enum MarkdownShortcutFormatter {
    static func edit(
        for shortcut: MarkdownShortcutKind,
        in text: NSString,
        selectedRange: NSRange
    ) -> MarkdownShortcutEdit {
        let range = normalizedRange(selectedRange, in: text)
        switch shortcut {
        case .bold:
            return wrappedEdit(prefix: "**", suffix: "**", in: text, selectedRange: range)
        case .italic:
            return wrappedEdit(prefix: "*", suffix: "*", in: text, selectedRange: range)
        case .link:
            return linkEdit(in: text, selectedRange: range)
        }
    }

    private static func wrappedEdit(
        prefix: String,
        suffix: String,
        in text: NSString,
        selectedRange: NSRange
    ) -> MarkdownShortcutEdit {
        let selectedText = text.substring(with: selectedRange)
        let replacement = prefix + selectedText + suffix
        let cursorOffset = (prefix as NSString).length
        let selectedLength = (selectedText as NSString).length

        return MarkdownShortcutEdit(
            replacementRange: selectedRange,
            replacementText: replacement,
            selectedRange: NSRange(
                location: selectedRange.location + cursorOffset,
                length: selectedLength
            )
        )
    }

    private static func linkEdit(in text: NSString, selectedRange: NSRange) -> MarkdownShortcutEdit {
        let selectedText = text.substring(with: selectedRange)
        let replacement = "[\(selectedText)]()"
        let cursorOffset: Int
        if selectedRange.length == 0 {
            cursorOffset = 1
        } else {
            cursorOffset = (selectedText as NSString).length + 3
        }

        return MarkdownShortcutEdit(
            replacementRange: selectedRange,
            replacementText: replacement,
            selectedRange: NSRange(location: selectedRange.location + cursorOffset, length: 0)
        )
    }

    private static func normalizedRange(_ selectedRange: NSRange, in text: NSString) -> NSRange {
        let location = min(max(selectedRange.location, 0), text.length)
        let length = min(max(selectedRange.length, 0), text.length - location)
        return NSRange(location: location, length: length)
    }
}
