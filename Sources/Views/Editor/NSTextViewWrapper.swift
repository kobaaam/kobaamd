import SwiftUI
import AppKit

struct NSTextViewWrapper: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    let binding: Binding<String>
    let scrollRatio: Binding<Double>

    private static let paperColor = NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1)
    // Fixed dark ink — never use NSColor.black (system-adaptive in macOS 26+)
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
        // NSTextView.scrollableTextView() is Apple's factory method that creates
        // a properly configured NSTextView+NSScrollView pair.
        // This handles all required setup: autoresizingMask, widthTracksTextView,
        // isVerticallyResizable, maxSize, etc. — the manual approach always misses
        // something and causes invisible text.
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            fatalError("scrollableTextView() must return NSTextView as documentView")
        }

        // Appearance
        scrollView.backgroundColor    = Self.paperColor
        scrollView.drawsBackground    = true

        // Force Aqua appearance so the text view is never in dark-mode context,
        // regardless of the system setting.  Without this, macOS 26 beta can
        // give the embedded NSTextView a dark effectiveAppearance even when
        // the SwiftUI window is using a light background.
        textView.appearance = NSAppearance(named: .aqua)

        // isRichText=true: rendering uses NSTextStorage attributes directly.
        // This is the ONLY reliable way to guarantee text colour on macOS 26+
        // when HighlightService modifies textStorage attributes.
        textView.isRichText           = true
        textView.font                 = Self.editorFont
        textView.textColor            = Self.inkColor
        textView.backgroundColor      = Self.paperColor
        textView.drawsBackground      = true
        textView.insertionPointColor  = Self.inkColor
        textView.isEditable           = true
        textView.isSelectable         = true
        textView.allowsUndo           = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.textContainerInset   = NSSize(width: 16, height: 16)

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

        // Use setAttributedString so the ink colour is baked into the storage
        // from the very first frame — before HighlightService runs async.
        // This avoids a one-frame flash of invisible text on macOS 26 beta.
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font:            Self.editorFont,
            .foregroundColor: Self.inkColor,
        ]
        let attrStr = NSAttributedString(string: binding.wrappedValue, attributes: baseAttrs)
        textView.textStorage?.setAttributedString(attrStr)

        textView.typingAttributes = baseAttrs

        let safeRange = NSRange(
            location: min(selectedRange.location, textView.string.count),
            length: 0
        )
        textView.setSelectedRange(safeRange)

        // Syntax highlighting (async to avoid layout conflicts during SwiftUI update)
        let tv = textView
        DispatchQueue.main.async {
            guard let ts = tv.textStorage else { return }
            context.coordinator.highlightService.highlight(ts)
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
