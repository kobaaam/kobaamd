import Foundation
import Testing
@testable import kobaamd

@Suite("MarkdownShortcutFormatter")
struct MarkdownShortcutFormatterTests {
    @Test("Bold wraps the current selection")
    func boldWrapsSelection() {
        let edit = MarkdownShortcutFormatter.edit(
            for: .bold,
            in: "hello world",
            selectedRange: NSRange(location: 6, length: 5)
        )

        #expect(edit.replacementRange == NSRange(location: 6, length: 5))
        #expect(edit.replacementText == "**world**")
        #expect(edit.selectedRange == NSRange(location: 8, length: 5))
    }

    @Test("Italic inserts paired markers when selection is empty")
    func italicInsertsPairedMarkersForCaret() {
        let edit = MarkdownShortcutFormatter.edit(
            for: .italic,
            in: "hello",
            selectedRange: NSRange(location: 5, length: 0)
        )

        #expect(edit.replacementRange == NSRange(location: 5, length: 0))
        #expect(edit.replacementText == "**")
        #expect(edit.selectedRange == NSRange(location: 6, length: 0))
    }

    @Test("Link wraps the current selection and moves the caret into the URL slot")
    func linkWrapsSelectionAndMovesCaret() {
        let edit = MarkdownShortcutFormatter.edit(
            for: .link,
            in: "hello",
            selectedRange: NSRange(location: 0, length: 5)
        )

        #expect(edit.replacementText == "[hello]()")
        #expect(edit.selectedRange == NSRange(location: 8, length: 0))
    }

    @Test("Link inserts an empty link scaffold at the caret")
    func linkInsertsEmptyScaffoldAtCaret() {
        let edit = MarkdownShortcutFormatter.edit(
            for: .link,
            in: "hello",
            selectedRange: NSRange(location: 5, length: 0)
        )

        #expect(edit.replacementText == "[]()")
        #expect(edit.selectedRange == NSRange(location: 6, length: 0))
    }
}
