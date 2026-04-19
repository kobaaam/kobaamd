import SwiftUI
import AppKit

struct NSTextViewWrapper: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    let binding: Binding<String>
    let scrollRatio: Binding<Double>

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self.binding = binding
        self.scrollRatio = scrollRatio
    }

    func makeCoordinator() -> Coordinator {
        .init(binding: binding, scrollRatio: scrollRatio)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let paperColor = NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1)
        let inkColor   = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)

        // ── ScrollView ───────────────────────────────────────────
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = paperColor
        scrollView.drawsBackground = true
        scrollView.appearance = NSAppearance(named: .aqua)

        // ── TextContainer: must track textView width ──────────────
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true   // ← wrap width follows textView

        // ── LayoutManager + TextStorage ──────────────────────────
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        // ── TextView ─────────────────────────────────────────────
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = inkColor
        textView.backgroundColor = paperColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true       // ← grow vertically with content
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]         // ← follow scrollView width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
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
        if textView.string != binding.wrappedValue {
            let selectedRange = textView.selectedRange()
            textView.string = binding.wrappedValue
            let safeRange = NSRange(location: min(selectedRange.location, textView.string.count), length: 0)
            textView.setSelectedRange(safeRange)
            if let ts = textView.textStorage {
                context.coordinator.highlightService.highlight(ts)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let binding: Binding<String>
        let scrollRatio: Binding<Double>
        let highlightService = HighlightService()

        init(binding: Binding<String>, scrollRatio: Binding<Double>) {
            self.binding = binding
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
            let visible = sv.documentVisibleRect.minY
            let total = sv.documentView?.frame.height ?? 1
            let viewportH = sv.frame.height
            let maxScroll = max(total - viewportH, 1)
            scrollRatio.wrappedValue = min(max(visible / maxScroll, 0), 1)
        }
    }
}
