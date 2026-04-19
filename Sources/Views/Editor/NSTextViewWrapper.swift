import SwiftUI
import AppKit

// MARK: - NSTextView-based editor with ruler and syntax highlighting
//
// Key lesson from macOS 26 beta investigation:
//   Setting textColor / backgroundColor / appearance on NSTextView while
//   inside a SwiftUI NSViewRepresentable causes the glyph-drawing layer to
//   lose its colour.  The root cause appears to be a SwiftUI↔AppKit appearance
//   injection conflict: SwiftUI assumes it owns appearance propagation, so any
//   explicit override on the NSView races with SwiftUI's own pass and may win
//   or lose unpredictably.
//
// Fix strategy — exactly what SwiftUI TextEditor does internally:
//   1. scrollView.drawsBackground = false  ← SwiftUI .background() provides colour
//   2. textView.drawsBackground  = false   ← same
//   3. textView.appearance = .aqua         ← resolves dynamic colours (labelColor→black)
//   4. do NOT set textView.textColor       ← let the system use textColor from appearance
//   5. typingAttributes / HighlightService use a FIXED sRGB ink colour

struct NSTextViewWrapper: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    let binding:     Binding<String>
    let scrollRatio: Binding<Double>

    // Fixed sRGB ink — independent of appearance / dynamic colour resolution
    private static let inkColor   = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)
    private static let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self.binding     = binding
        self.scrollRatio = scrollRatio
    }

    func makeCoordinator() -> Coordinator {
        .init(binding: binding, scrollRatio: scrollRatio)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            fatalError("scrollableTextView() must return NSTextView as documentView")
        }

        // ── Background: let SwiftUI parent supply the paper colour ──────────
        // Setting these to false makes both views transparent so the SwiftUI
        // .background(Color.kobaPaper) behind this NSViewRepresentable shows
        // through — exactly the same as what TextEditor does internally.
        scrollView.drawsBackground         = false
        scrollView.contentView.drawsBackground = false
        textView.drawsBackground           = false

        // ── Appearance: Aqua so dynamic colours resolve to light-mode values ─
        // Without this, on macOS 26 beta the effectiveAppearance can be Dark
        // even when the window is light-themed, making labelColor = white.
        textView.appearance = NSAppearance(named: .aqua)

        // ── Text settings ────────────────────────────────────────────────────
        textView.isRichText           = true   // attributes in textStorage drive rendering
        textView.font                 = Self.editorFont
        textView.insertionPointColor  = Self.inkColor
        textView.isEditable           = true
        textView.isSelectable         = true
        textView.allowsUndo           = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.textContainerInset   = NSSize(width: 16, height: 16)

        // Typing attributes ensure new text is ink-coloured immediately
        textView.typingAttributes = [
            .font:            Self.editorFont,
            .foregroundColor: Self.inkColor,
        ]

        textView.delegate = context.coordinator

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrolled(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )

        LineNumberRulerView.install(on: scrollView, textView: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        guard textView.string != binding.wrappedValue else { return }

        let selectedRange = textView.selectedRange()

        // Set attributed string so ink colour is baked in from frame 1,
        // before HighlightService runs its async pass.
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font:            Self.editorFont,
            .foregroundColor: Self.inkColor,
        ]
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: binding.wrappedValue, attributes: baseAttrs)
        )
        textView.typingAttributes = baseAttrs

        let safeRange = NSRange(
            location: min(selectedRange.location, textView.string.count),
            length: 0
        )
        textView.setSelectedRange(safeRange)

        // Syntax highlighting — deferred to avoid layout conflicts during update
        let tv = textView
        DispatchQueue.main.async {
            guard let ts = tv.textStorage else { return }
            context.coordinator.highlightService.highlight(ts)
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let binding:      Binding<String>
        let scrollRatio:  Binding<Double>
        let highlightService = HighlightService()

        init(binding: Binding<String>, scrollRatio: Binding<Double>) {
            self.binding     = binding
            self.scrollRatio = scrollRatio
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let ts       = textView.textStorage else { return }
            binding.wrappedValue = textView.string
            highlightService.highlight(ts)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        @objc func scrolled(_ notification: Notification) {
            guard let sv = notification.object as? NSScrollView else { return }
            let visible   = sv.documentVisibleRect.minY
            let total     = sv.documentView?.frame.height ?? 1
            let viewportH = sv.frame.height
            let maxScroll = max(total - viewportH, 1)
            scrollRatio.wrappedValue = min(max(visible / maxScroll, 0), 1)
        }
    }
}
