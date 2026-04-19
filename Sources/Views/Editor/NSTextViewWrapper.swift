import SwiftUI
import AppKit

// MARK: - Editor text area
//
// NSTextView inside NSViewRepresentable renders INVISIBLE text on macOS 26 beta.
// Fix: NSViewControllerRepresentable gives us viewDidAppear, which fires AFTER
// SwiftUI's appearance injection completes. We apply colors only there.
//
// Auto-completion rules (Markdown):
//   **  →  ****  (cursor between pairs)
//   *   →  **
//   `   →  ``
//   [   →  []()
//   Enter in list → continue bullet / numbered list

private let inkColor   = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)
private let paperColor = NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1)
private let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

// MARK: - View Controller

final class EditorViewController: NSViewController {
    var onTextChange: ((String) -> Void)?
    var initialText: String = ""

    private(set) var textView: NSTextView!
    private var scrollView: NSScrollView!

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled   = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.autoresizingMask = .width
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.font = editorFont
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        scrollView.documentView = textView
        self.view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.string = initialText
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Apply colors AFTER SwiftUI appearance injection completes (macOS 26 fix)
        applyColors()
        DispatchQueue.main.async { [weak self] in
            self?.applyColors()
        }
    }

    func applyColors() {
        textView.backgroundColor = paperColor
        textView.drawsBackground = true
        textView.textColor = inkColor
        textView.typingAttributes = [
            .font: editorFont,
            .foregroundColor: inkColor
        ]
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: inkColor,
                             range: NSRange(location: 0, length: storage.length))
        storage.addAttribute(.font, value: editorFont,
                             range: NSRange(location: 0, length: storage.length))
    }

    func setTextExternally(_ text: String) {
        guard textView.string != text else { return }
        let sel = textView.selectedRange()
        textView.string = text
        applyColors()
        let length = (textView.string as NSString).length
        let clampedLoc = min(sel.location, length)
        textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
    }
}

// MARK: - NSViewControllerRepresentable

struct NSTextViewWrapper: NSViewControllerRepresentable {
    @Binding var text: String
    @Binding var scrollRatio: Double   // reserved — not yet exported

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self._text        = binding
        self._scrollRatio = scrollRatio
    }

    func makeNSViewController(context: Context) -> EditorViewController {
        let vc = EditorViewController()
        vc.initialText = text
        _ = vc.view  // Force loadView() + viewDidLoad() before updateNSViewController
        vc.textView.delegate = context.coordinator
        return vc
    }

    func updateNSViewController(_ vc: EditorViewController, context: Context) {
        // Keep delegate current (e.g. after coordinator is replaced)
        vc.textView.delegate = context.coordinator
        // Only sync text if SwiftUI changed it externally
        if vc.textView.string != text {
            vc.setTextExternally(text)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator (delegate + auto-completion)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NSTextViewWrapper
        private var isApplyingCompletion = false

        init(_ parent: NSTextViewWrapper) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView,
                      shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard !isApplyingCompletion, let str = replacementString else { return true }

            switch str {
            case "**":
                return insertPair(textView, in: range, open: "**", close: "**")
            case "*":
                return insertPair(textView, in: range, open: "*", close: "*")
            case "`":
                return insertPair(textView, in: range, open: "`", close: "`")
            case "[":
                return insertPair(textView, in: range, open: "[", close: "]()")
            case "\n":
                let source = textView.string as NSString
                let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
                let line = source.substring(with: lineRange)
                if let continuation = listContinuation(for: line) {
                    isApplyingCompletion = true
                    textView.insertText("\n" + continuation, replacementRange: range)
                    isApplyingCompletion = false
                    return false
                }
                return true
            default:
                return true
            }
        }

        private func insertPair(_ textView: NSTextView,
                                in range: NSRange,
                                open: String,
                                close: String) -> Bool {
            isApplyingCompletion = true
            textView.insertText(open + close, replacementRange: range)
            let newCursor = range.location + open.count
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            isApplyingCompletion = false
            return false
        }

        private func listContinuation(for line: String) -> String? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["- ", "* ", "+ "] {
                if trimmed.hasPrefix(prefix) {
                    let content = String(trimmed.dropFirst(prefix.count))
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                    let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                    return indent + prefix
                }
            }
            // Ordered list: "1. ", "2. ", etc.
            let numberedPattern = #"^(\s*)(\d+)\. "#
            if let regex = try? NSRegularExpression(pattern: numberedPattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let numRange = Range(match.range(at: 2), in: line),
               let num = Int(line[numRange]) {
                let content = String(line.dropFirst(match.range.length))
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                return "\(indent)\(num + 1). "
            }
            return nil
        }
    }
}
