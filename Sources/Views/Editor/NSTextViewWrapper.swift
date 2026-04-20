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
    @Binding var scrollRatio: Double   // drives editor↔preview sync
    var fileURL: URL?                  // used by image-paste to resolve ./assets/

    // Fixed sRGB values, matching HighlightService (labelColor goes white on macOS 26 dark).
    fileprivate static let inkColor   = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)
    fileprivate static let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    init(binding: Binding<String>, scrollRatio: Binding<Double>, fileURL: URL? = nil) {
        self._text        = binding
        self._scrollRatio = scrollRatio
        self.fileURL      = fileURL
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
        // Observe scroll events to drive editor↔preview sync via scrollRatio binding.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
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

        // MARK: Scroll sync

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = notification.object as? NSScrollView,
                  let textView = scrollView.documentView as? NSTextView else { return }
            let pos = scrollView.contentView.bounds.minY
            let total = textView.bounds.height - scrollView.contentSize.height
            parent.scrollRatio = total > 0 ? max(0, min(1, pos / total)) : 0
        }

        // MARK: Image paste

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == NSSelectorFromString("paste:") {
                return handleImagePaste(in: textView)
            }
            return false
        }

        /// Intercepts paste when the clipboard contains an image.
        /// Saves it to ./assets/ beside the open file, then inserts a Markdown image link.
        private func handleImagePaste(in textView: NSTextView) -> Bool {
            let pb = NSPasteboard.general
            guard let image = NSImage(pasteboard: pb) else { return false }

            // Resolve ./assets/ directory relative to the currently open file.
            guard let fileURL = parent.fileURL,
                  let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return false }

            let assetsDir = fileURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                let fileName = "image-\(Int(Date().timeIntervalSince1970)).png"
                let destURL = assetsDir.appendingPathComponent(fileName)
                try pngData.write(to: destURL)
                let mdLink = "![](./assets/\(fileName))"
                textView.insertText(mdLink, replacementRange: textView.selectedRange)
                return true
            } catch {
                return false
            }
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

    // MARK: - Markdown auto-completion

    private static let bracketPairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"
    ]

    override func keyDown(with event: NSEvent) {
        if handleMarkdownKey(event) { return }
        super.keyDown(with: event)
    }

    private func handleMarkdownKey(_ event: NSEvent) -> Bool {
        guard let chars = event.characters, let first = chars.first else { return false }
        switch first {
        case "\t":
            insertText("    ", replacementRange: selectedRange)
            return true
        case "\u{7f}", "\u{08}":
            return handleSmartBackspace()
        case "\r", "\n":
            return handleNewline()
        default:
            guard Self.bracketPairs.keys.contains(first) else { return false }
            handleBracketCompletion(for: first)
            return true
        }
    }

    private func handleBracketCompletion(for opening: Character) {
        guard let closing = Self.bracketPairs[opening] else { return }
        let range = selectedRange
        if range.length > 0 {
            let selection = (string as NSString).substring(with: range)
            insertText("\(opening)\(selection)\(closing)", replacementRange: range)
            selectedRange = NSRange(location: range.location + 1, length: range.length)
        } else {
            insertText("\(opening)\(closing)", replacementRange: range)
            selectedRange = NSRange(location: range.location + 1, length: 0)
        }
    }

    private func handleSmartBackspace() -> Bool {
        let location = selectedRange.location
        guard selectedRange.length == 0, location > 0 else { return false }
        let ns = string as NSString
        guard location < ns.length else { return false }
        let prev = Character(ns.substring(with: NSRange(location: location - 1, length: 1)))
        let next = Character(ns.substring(with: NSRange(location: location, length: 1)))
        guard let expected = Self.bracketPairs[prev], expected == next else { return false }
        insertText("", replacementRange: NSRange(location: location - 1, length: 2))
        return true
    }

    private func handleNewline() -> Bool {
        let ns = string as NSString
        let location = selectedRange.location
        let lineRange = ns.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
        let prefixLen = location - lineRange.location
        guard prefixLen >= 0 else { return false }
        let lineText = prefixLen > 0 ? ns.substring(with: NSRange(location: lineRange.location, length: prefixLen)) : ""
        if handleFenceInsertion(lineText: lineText, cursorLocation: location) { return true }
        if handleListContinuation(lineText: lineText, lineRange: lineRange, prefixLen: prefixLen) { return true }
        return false
    }

    private func handleFenceInsertion(lineText: String, cursorLocation: Int) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```"), trimmed.count >= 3 else { return false }
        let indent = String(lineText.prefix { $0.isWhitespace })
        let newline = "\n" + indent
        let closing = "\n" + indent + "```"
        insertText(newline + closing, replacementRange: NSRange(location: cursorLocation, length: 0))
        selectedRange = NSRange(location: cursorLocation + newline.utf16.count, length: 0)
        return true
    }

    private func handleListContinuation(lineText: String, lineRange: NSRange, prefixLen: Int) -> Bool {
        guard let (indent, marker, content) = parseListMarker(in: lineText) else { return false }
        let ns = string as NSString
        let lineEnd = lineRange.location + lineRange.length
        let tail = lineEnd > selectedRange.location
            ? ns.substring(with: NSRange(location: selectedRange.location, length: lineEnd - selectedRange.location))
            : ""
        guard tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        // Empty item → exit list mode.
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            let removalRange = NSRange(location: lineRange.location, length: prefixLen)
            insertText("", replacementRange: removalRange)
            insertText("\n", replacementRange: NSRange(location: lineRange.location, length: 0))
            selectedRange = NSRange(location: lineRange.location + 1, length: 0)
        } else {
            // Increment ordered list numbers.
            let nextMarker = nextListMarker(from: marker)
            insertText("\n" + indent + nextMarker + " ",
                       replacementRange: NSRange(location: selectedRange.location, length: 0))
        }
        return true
    }

    private func parseListMarker(in line: String) -> (indent: String, marker: String, content: String)? {
        let indentEnd = line.firstIndex(where: { !$0.isWhitespace }) ?? line.endIndex
        let indent = String(line[..<indentEnd])
        let rest = String(line[indentEnd...])
        for bullet in ["-", "*", "+"] {
            if rest.hasPrefix(bullet + " ") {
                return (indent, bullet, String(rest.dropFirst(bullet.count + 1)))
            }
        }
        // Ordered list: "123. "
        let digits = rest.prefix(while: { $0.isNumber })
        if !digits.isEmpty {
            let afterDigits = rest.dropFirst(digits.count)
            if afterDigits.hasPrefix(". ") {
                return (indent, String(digits) + ".", String(afterDigits.dropFirst(2)))
            }
        }
        return nil
    }

    private func nextListMarker(from marker: String) -> String {
        guard marker.hasSuffix("."),
              let n = Int(marker.dropLast()) else { return marker }
        return "\(n + 1)."
    }
}
