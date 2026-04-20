import SwiftUI
import AppKit

// NSTextView via NSViewRepresentable with HighlightService integration.
//
// macOS 26 invisible-text fix (history in memory/feedback_nstextview_macos26.md):
//   • NEVER set textColor / backgroundColor in makeNSView or updateNSView.
//   • Colors are applied only inside KobaTextView.viewDidMoveToWindow, deferred
//     one run-loop turn so SwiftUI appearance injection has already settled.
//   • typingAttributes always carries the fixed sRGB ink color so newly typed
//     characters are immediately visible.
//
struct NSTextViewWrapper: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollRatio: Double   // reserved — not yet exported

    // Fixed sRGB values, matching HighlightService (labelColor goes white on macOS 26 dark).
    fileprivate static let inkColor   = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)
    fileprivate static let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self._text        = binding
        self._scrollRatio = scrollRatio
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = KobaTextView()
        textView.delegate = context.coordinator

        // Structural setup only — NO colour / font here (avoids macOS 26 invisible text).
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true          // required to hold NSTextStorage attributes
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false    // SwiftUI layer provides the background
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Seed the text content (guard flag prevents spurious delegate callback).
        context.coordinator.isUpdating = true
        textView.string = text
        context.coordinator.isUpdating = false

        // Colors and initial highlight run once the window is visible.
        textView.onFirstAppear = { [weak textView] in
            guard let tv = textView else { return }
            context.coordinator.applyColors(to: tv)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        // Attach line number ruler (already implemented in LineNumberRulerView).
        LineNumberRulerView.install(on: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }

        // External text update (file open) — re-highlight after replacing.
        let selectedRanges = textView.selectedRanges
        context.coordinator.isUpdating = true
        textView.string = text
        context.coordinator.applyHighlight(to: textView)
        let len = textView.string.count
        textView.selectedRanges = selectedRanges.map { value in
            let r = value.rangeValue
            let clampedLoc = min(r.location, len)
            let clampedLen = min(r.length, len - clampedLoc)
            return NSValue(range: NSRange(location: clampedLoc, length: clampedLen))
        }
        context.coordinator.isUpdating = false
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NSTextViewWrapper
        var isUpdating = false
        private let highlighter = HighlightService()

        init(parent: NSTextViewWrapper) {
            self.parent = parent
        }

        /// Called once by KobaTextView after the window is visible — safe to set colors.
        func applyColors(to textView: NSTextView) {
            textView.typingAttributes = [
                .foregroundColor: NSTextViewWrapper.inkColor,
                .font: NSTextViewWrapper.editorFont,
            ]
            applyHighlight(to: textView)
        }

        /// Re-highlights the full document.
        func applyHighlight(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            // Keep typingAttributes in sync so new input uses the correct color.
            textView.typingAttributes[.foregroundColor] = NSTextViewWrapper.inkColor
            textView.typingAttributes[.font]            = NSTextViewWrapper.editorFont

            let prev = isUpdating
            isUpdating = true
            highlighter.highlight(storage)
            isUpdating = prev
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            // Push text to SwiftUI binding before highlighting.
            parent.text = textView.string
            applyHighlight(to: textView)
            // Refresh line number ruler.
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

// MARK: - KobaTextView

/// NSTextView subclass that fires onFirstAppear once the parent window becomes visible.
/// This is the macOS 26 colour-timing workaround: colours are applied only after
/// SwiftUI's appearance injection is complete.
private final class KobaTextView: NSTextView {
    var onFirstAppear: (() -> Void)?
    private var appeared = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !appeared, window != nil else { return }
        appeared = true
        // One run-loop deferral so SwiftUI appearance injection settles first.
        DispatchQueue.main.async { [weak self] in
            self?.onFirstAppear?()
        }
    }
}
