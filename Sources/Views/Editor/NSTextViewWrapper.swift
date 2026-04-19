import SwiftUI
import AppKit

struct NSTextViewWrapper: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    let binding: Binding<String>
    let scrollRatio: Binding<Double>

    private static let paperColor = NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1)
    private static let inkColor   = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)
    private static let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    // Default attributes applied to ALL text before syntax highlighting
    private static let baseAttrs: [NSAttributedString.Key: Any] = [
        .font:            editorFont,
        .foregroundColor: inkColor,
    ]

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self.binding    = binding
        self.scrollRatio = scrollRatio
    }

    func makeCoordinator() -> Coordinator {
        .init(binding: binding, scrollRatio: scrollRatio)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // ── ScrollView ───────────────────────────────────────────
        let scrollView = NSScrollView()
        scrollView.borderType        = .noBorder
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.backgroundColor    = Self.paperColor
        scrollView.drawsBackground    = true
        // Force aqua appearance so system colors resolve in light mode context
        scrollView.appearance = NSAppearance(named: .aqua)

        // ── TextView — start with non-zero width so layout is valid ──
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        // isRichText = true → NSTextView USES .foregroundColor from textStorage
        // (with isRichText=false the textView IGNORES storage attributes and uses
        //  the textColor property, which caused the invisible-text bug)
        textView.isRichText  = true
        textView.font        = Self.editorFont
        textView.backgroundColor = Self.paperColor

        // Proper scroll/resize setup (required for NSTextView in NSScrollView)
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask        = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.isEditable   = true
        textView.isSelectable = true
        textView.allowsUndo   = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.delegate = context.coordinator

        scrollView.documentView = textView

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

        // Explicitly set foreground color so text is ALWAYS visible.
        // With isRichText=true, NSTextView uses .foregroundColor from textStorage.
        // We set it here (inkColor = #1a1a1a) before HighlightService overlays
        // syntax-specific colors.
        let attrStr = NSAttributedString(string: binding.wrappedValue,
                                         attributes: Self.baseAttrs)
        textView.textStorage?.setAttributedString(attrStr)

        let safeRange = NSRange(
            location: min(selectedRange.location, textView.string.count),
            length: 0
        )
        textView.setSelectedRange(safeRange)

        // Apply syntax highlighting asynchronously to avoid layout conflicts
        // during SwiftUI's update pass
        DispatchQueue.main.async {
            guard let ts = textView.textStorage else { return }
            context.coordinator.highlightService.highlight(ts)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let binding: Binding<String>
        let scrollRatio: Binding<Double>
        let highlightService = HighlightService()

        init(binding: Binding<String>, scrollRatio: Binding<Double>) {
            self.binding     = binding
            self.scrollRatio = scrollRatio
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let textStorage = textView.textStorage else { return }
            binding.wrappedValue = textView.string
            highlightService.highlight(textStorage)
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
