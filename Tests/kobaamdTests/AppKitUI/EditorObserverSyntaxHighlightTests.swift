import AppKit
import Testing
@testable import kobaamd

@MainActor
@Suite("EditorObserver syntax highlight wiring")
struct EditorObserverSyntaxHighlightTests {

    @Test("applySyntaxHighlight は初回に full highlight を使う")
    func applySyntaxHighlightUsesFullHighlight() {
        let highlighter = RecordingHighlightService()
        let coordinator = EditorObserver.Coordinator(highlightService: highlighter)
        let textView = NSTextView()
        textView.string = "# Heading"

        coordinator.applySyntaxHighlight(in: textView)

        #expect(highlighter.fullHighlightCalls == 1)
        #expect(highlighter.incrementalCalls.isEmpty)
    }

    @Test("applySyntaxHighlight は編集情報があれば incremental highlight を使う")
    func applySyntaxHighlightUsesIncrementalHighlightForEdits() {
        let highlighter = RecordingHighlightService()
        let coordinator = EditorObserver.Coordinator(highlightService: highlighter)
        let textView = NSTextView()
        textView.string = "# Heading"

        coordinator.applySyntaxHighlight(
            in: textView,
            editedRange: NSRange(location: 0, length: 2),
            changeInLength: 1
        )

        #expect(highlighter.fullHighlightCalls == 0)
        #expect(highlighter.incrementalCalls.count == 1)
        #expect(highlighter.incrementalCalls[0].editedRange == NSRange(location: 0, length: 2))
        #expect(highlighter.incrementalCalls[0].changeInLength == 1)
    }

    @Test("theme change refresh は syntax highlight を再適用する")
    func refreshHighlightForThemeChangeReappliesSyntaxHighlight() {
        let highlighter = RecordingHighlightService()
        let coordinator = EditorObserver.Coordinator(highlightService: highlighter)
        let textView = NSTextView()
        textView.string = "# Heading\nBody"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        coordinator.refreshHighlightForThemeChange(in: textView)

        #expect(highlighter.fullHighlightCalls == 1)
    }
}

@MainActor
private final class RecordingHighlightService: HighlightServiceProtocol {
    struct IncrementalCall {
        let editedRange: NSRange
        let changeInLength: Int
    }

    private(set) var fullHighlightCalls = 0
    private(set) var incrementalCalls: [IncrementalCall] = []

    func highlight(_ textStorage: NSTextStorage) {
        fullHighlightCalls += 1
    }

    func applyIncrementalHighlight(
        textStorage: NSTextStorage,
        editedRange: NSRange,
        changeInLength: Int
    ) {
        incrementalCalls.append(
            IncrementalCall(
                editedRange: editedRange,
                changeInLength: changeInLength
            )
        )
    }
}
