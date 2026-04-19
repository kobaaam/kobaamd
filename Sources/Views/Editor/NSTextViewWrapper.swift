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
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
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
