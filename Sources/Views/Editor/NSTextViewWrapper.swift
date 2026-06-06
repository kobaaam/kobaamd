import SwiftUI
import AppKit

// MARK: - Editor text area
//
// NSTextView in NSViewRepresentable renders INVISIBLE text on macOS 26 beta.
// NSViewControllerRepresentable (viewDidAppear approach) is confirmed HEAVY.
// SwiftUI TextEditor is the lightest and most reliable solution.
//
// Markdown auto-completion is deferred to Phase 3 (requires working NSTextView).

struct NSTextViewWrapper: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable var appState = AppState.shared
    @Binding var text: String
    @Binding var scrollRatio: Double

    private var paperColor: Color { Color(appState.selectedTheme.editorBackground) }
    private var inkColor: Color   { Color(appState.selectedTheme.editorText) }
    private static let editorFont = Font.system(size: 14, design: .monospaced)

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self._text        = binding
        self._scrollRatio = scrollRatio
    }

    var body: some View {
        TextEditor(text: $text)
            .font(Self.editorFont)
            .lineSpacing(6)
            .foregroundStyle(inkColor)
            .scrollContentBackground(.hidden)
            .background(
                ZStack {
                    paperColor
                    EditorObserver(scrollRatio: $scrollRatio, appViewModel: appViewModel)
                }
            )
            .padding(.horizontal, 4)
    }
}

// MARK: - Editor observer (scroll ratio + current line highlight)

/// TextEditor 配下の NSScrollView / NSTextView を検出して
/// ① スクロール比率を binding に流す
/// ② カーソル行を temporaryAttribute でハイライト（ドキュメント非破壊）
struct EditorObserver: NSViewRepresentable {
    @Binding var scrollRatio: Double
    let appViewModel: AppViewModel
    @Bindable var appState = AppState.shared

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        context.coordinator.appViewModel = appViewModel
        context.coordinator.currentTheme = appState.selectedTheme
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            context.coordinator.attach(to: view, scrollRatio: $scrollRatio)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.appViewModel = appViewModel
        let newTheme = appState.selectedTheme
        if context.coordinator.currentTheme != newTheme {
            context.coordinator.currentTheme = newTheme
            if let tv = context.coordinator.textViewRef {
                MainActor.assumeIsolated {
                    context.coordinator.refreshHighlightForThemeChange(in: tv)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var scrollObserver: Any?
        private var selectionObserver: Any?
        private var textDidChangeObserver: Any?
        private var insertSnippetObserver: Any?
        private var toggleBoldObserver: Any?
        private var toggleItalicObserver: Any?
        private var insertLinkObserver: Any?
        private var eventMonitor: Any?
        private let highlightService: HighlightServiceProtocol
        weak var textViewRef: NSTextView?
        weak var appViewModel: AppViewModel?
        var currentTheme: ColorTheme = AppState.shared.selectedTheme
        var highlightColor: NSColor { currentTheme.editorCurrentLineHighlight }
        private var lastHighlightedRange: NSRange = NSRange(location: NSNotFound, length: 0)

        @MainActor
        init(highlightService: HighlightServiceProtocol? = nil) {
            self.highlightService = highlightService ?? TreeSitterHighlightService()
        }

        func attach(to view: NSView, scrollRatio: Binding<Double>) {
            var current: NSView? = view
            var foundScrollView = false
            var foundTextView = false

            for _ in 0..<25 {
                guard let parent = current?.superview else { break }

                // NSScrollView を探してスクロール比率を購読
                if !foundScrollView,
                   let sv = findView(NSScrollView.self, in: parent, excluding: current, where: { $0.documentView is NSTextView }) {
                    subscribeScroll(sv, ratio: scrollRatio)
                    foundScrollView = true
                }

                // NSTextView を探してライン ハイライトを設定
                if !foundTextView,
                   let tv = findView(NSTextView.self, in: parent, excluding: current) {
                    subscribeSelection(tv)
                    foundTextView = true
                }

                if foundScrollView && foundTextView { break }
                current = parent
            }

            NotificationCenter.default.addObserver(
                forName: .e1FocusEditorRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let tv = self?.textViewRef else { return }
                tv.window?.makeFirstResponder(tv)
            }

            insertSnippetObserver = NotificationCenter.default.addObserver(
                forName: .insertSnippetAtCursor,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let tv = self?.textViewRef,
                      let text = note.userInfo?["text"] as? String else { return }
                let range = tv.selectedRange()
                tv.insertText(text, replacementRange: range)
            }

            toggleBoldObserver = NotificationCenter.default.addObserver(
                forName: .toggleBoldRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let tv = self.textViewRef, tv.window?.firstResponder === tv else { return }
                self.applyMarkdownShortcut(.bold, in: tv)
            }

            toggleItalicObserver = NotificationCenter.default.addObserver(
                forName: .toggleItalicRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let tv = self.textViewRef, tv.window?.firstResponder === tv else { return }
                self.applyMarkdownShortcut(.italic, in: tv)
            }

            insertLinkObserver = NotificationCenter.default.addObserver(
                forName: .insertLinkRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let tv = self.textViewRef, tv.window?.firstResponder === tv else { return }
                self.applyMarkdownShortcut(.link, in: tv)
            }
        }

        // MARK: - Scroll

        private func subscribeScroll(_ sv: NSScrollView, ratio: Binding<Double>) {
            sv.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: sv.contentView,
                queue: .main
            ) { [weak self, weak sv] _ in
                guard let sv else { return }
                let docHeight = sv.documentView?.frame.height ?? 1
                let visHeight = sv.contentView.bounds.height
                let maxScroll = max(docHeight - visHeight, 1)
                let r = sv.contentView.bounds.origin.y / maxScroll
                ratio.wrappedValue = max(0, min(1, r))
            }
        }

        // MARK: - Line highlight

        private func subscribeSelection(_ tv: NSTextView) {
            textViewRef = tv
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: tv,
                queue: .main
            ) { [weak self, weak tv] _ in
                guard let self, let tv else { return }
                self.highlightCurrentLine(in: tv)
            }
            textDidChangeObserver = NotificationCenter.default.addObserver(
                forName: NSText.didChangeNotification,
                object: tv,
                queue: .main
            ) { [weak self, weak tv] _ in
                guard let self, let tv else { return }
                MainActor.assumeIsolated {
                    self.highlightEditedText(in: tv)
                }
            }

            MainActor.assumeIsolated {
                applySyntaxHighlight(in: tv)
            }
            highlightCurrentLine(in: tv)

            // Return キーで箇条書き自動継続
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let tv = self.textViewRef,
                      tv.window?.firstResponder === tv
                else { return event }

                let mods = event.modifierFlags.intersection([.shift, .option, .command, .control])

                guard event.keyCode == 36, // Return
                      !tv.hasMarkedText(),
                      mods.isEmpty
                else { return event }

                return self.handleAutoListReturn(in: tv) ? nil : event
            }
        }

        // MARK: - Auto list continuation

        @discardableResult
        func applyMarkdownShortcut(_ shortcut: MarkdownShortcutKind, in tv: NSTextView) -> Bool {
            let nsString = tv.string as NSString
            let edit = MarkdownShortcutFormatter.edit(
                for: shortcut,
                in: nsString,
                selectedRange: tv.selectedRange()
            )

            guard let textStorage = tv.textStorage,
                  tv.shouldChangeText(in: edit.replacementRange, replacementString: edit.replacementText)
            else { return false }

            textStorage.replaceCharacters(in: edit.replacementRange, with: edit.replacementText)
            tv.didChangeText()
            tv.setSelectedRange(edit.selectedRange)
            return true
        }

        /// 現在行のリストプレフィックスを検出して自動継続。
        /// 処理した場合は true を返す（イベントを消費）。
        @discardableResult
        private func handleAutoListReturn(in tv: NSTextView) -> Bool {
            let nsString = tv.string as NSString
            let insertion = min(tv.selectedRange().location, nsString.length)
            let lineRange = nsString.lineRange(for: NSRange(location: insertion, length: 0))
            let currentLine = nsString.substring(with: lineRange)

            // タスクリスト（チェック済みも未チェックも → 未チェックで継続）
            let taskPrefixes = ["- [ ] ", "- [x] ", "- [X] "]
            for prefix in taskPrefixes {
                if currentLine.hasPrefix(prefix) {
                    let content = currentLine.dropFirst(prefix.count).trimmingCharacters(in: .newlines)
                    if content.isEmpty {
                        tv.insertText("", replacementRange: lineRange) // 空行なら記号を消す
                    } else {
                        tv.insertText("\n- [ ] ", replacementRange: tv.selectedRange())
                    }
                    return true
                }
            }

            // 順序なしリスト
            let unorderedPrefixes = ["- ", "* ", "+ "]
            for prefix in unorderedPrefixes {
                if currentLine.hasPrefix(prefix) {
                    let content = currentLine.dropFirst(prefix.count).trimmingCharacters(in: .newlines)
                    if content.isEmpty {
                        tv.insertText("", replacementRange: lineRange)
                    } else {
                        tv.insertText("\n" + prefix, replacementRange: tv.selectedRange())
                    }
                    return true
                }
            }

            // 順序付きリスト（例: "1. ", "2. "）
            let orderedRegex = try? NSRegularExpression(pattern: "^(\\d+)\\. ")
            if let match = orderedRegex?.firstMatch(in: currentLine,
                                                    range: NSRange(currentLine.startIndex..., in: currentLine)) {
                let numStr = (currentLine as NSString).substring(with: match.range(at: 1))
                if let num = Int(numStr) {
                    let prefixLen = numStr.count + 2 // "N. "
                    let content = currentLine.dropFirst(prefixLen).trimmingCharacters(in: .newlines)
                    if content.isEmpty {
                        tv.insertText("", replacementRange: lineRange)
                    } else {
                        tv.insertText("\n\(num + 1). ", replacementRange: tv.selectedRange())
                    }
                    return true
                }
            }

            return false
        }

        @MainActor
        func refreshHighlightForThemeChange(in tv: NSTextView) {
            applySyntaxHighlight(in: tv)
            if let lm = tv.layoutManager, lastHighlightedRange.location != NSNotFound {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: lastHighlightedRange)
            }
            lastHighlightedRange = NSRange(location: NSNotFound, length: 0)
            highlightCurrentLine(in: tv)
        }

        @MainActor
        func applySyntaxHighlight(
            in tv: NSTextView,
            editedRange: NSRange? = nil,
            changeInLength: Int = 0
        ) {
            guard let textStorage = tv.textStorage else { return }

            if let editedRange, editedRange.location != NSNotFound {
                highlightService.applyIncrementalHighlight(
                    textStorage: textStorage,
                    editedRange: editedRange,
                    changeInLength: changeInLength
                )
                return
            }

            highlightService.highlight(textStorage)
        }

        @MainActor
        func highlightEditedText(in tv: NSTextView) {
            guard let textStorage = tv.textStorage else { return }

            let editedRange = textStorage.editedRange
            let changeInLength = textStorage.changeInLength

            if editedRange.location == NSNotFound {
                applySyntaxHighlight(in: tv)
                return
            }

            applySyntaxHighlight(
                in: tv,
                editedRange: editedRange,
                changeInLength: changeInLength
            )
        }

        private func highlightCurrentLine(in tv: NSTextView) {
            guard let lm = tv.layoutManager else { return }
            let nsString = tv.string as NSString
            let fullLength = nsString.length
            guard fullLength > 0 else { return }

            let insertion = min(tv.selectedRange().location, fullLength)
            let lineRange = nsString.lineRange(for: NSRange(location: insertion, length: 0))

            // 前回行のハイライトだけ消す（全体リセットは高コストのため避ける）
            if lastHighlightedRange.location != NSNotFound {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: lastHighlightedRange)
            }

            lm.addTemporaryAttribute(.backgroundColor, value: highlightColor, forCharacterRange: lineRange)
            lastHighlightedRange = lineRange

            // プレビュー側にカーソルのブロックインデックスを通知
            let beforeCursor = String(tv.string.prefix(insertion))
            let blockIndex = beforeCursor
                .components(separatedBy: "\n\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
            NotificationCenter.default.post(
                name: .cursorBlockChanged,
                object: nil,
                userInfo: ["blockIndex": max(0, blockIndex - 1)]
            )
        }

        // MARK: - Generic view search

        /// root のサブツリーを再帰探索して条件を満たす T を返す。
        /// excluding ブランチはスキップ（ループ防止）。
        private func findView<T: NSView>(
            _ type: T.Type,
            in root: NSView,
            excluding: NSView?,
            where predicate: ((T) -> Bool)? = nil
        ) -> T? {
            for sub in root.subviews {
                if let excl = excluding, sub === excl { continue }
                if let typed = sub as? T, predicate?(typed) ?? true { return typed }
                if let found = findView(type, in: sub, excluding: nil, where: predicate) { return found }
            }
            return nil
        }

        deinit {
            [
                scrollObserver,
                selectionObserver,
                textDidChangeObserver,
                insertSnippetObserver,
                toggleBoldObserver,
                toggleItalicObserver,
                insertLinkObserver
            ]
            .compactMap { $0 }
            .forEach {
                NotificationCenter.default.removeObserver($0)
            }
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        }
    }
}
