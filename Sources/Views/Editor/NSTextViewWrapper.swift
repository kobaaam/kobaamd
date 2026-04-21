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
    @Binding var text: String
    @Binding var scrollRatio: Double

    private static let paperColor = Color(NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1))
    private static let inkColor   = Color(NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1))
    private static let editorFont = Font.system(size: 14, design: .monospaced)

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self._text        = binding
        self._scrollRatio = scrollRatio
    }

    var body: some View {
        TextEditor(text: $text)
            .font(Self.editorFont)
            .foregroundStyle(Self.inkColor)
            .scrollContentBackground(.hidden)
            .background(
                ZStack {
                    Self.paperColor
                    EditorObserver(scrollRatio: $scrollRatio)
                }
            )
            .padding(.horizontal, 4)
    }
}

// MARK: - Editor observer (scroll ratio + current line highlight)

/// TextEditor 配下の NSScrollView / NSTextView を検出して
/// ① スクロール比率を binding に流す
/// ② カーソル行を temporaryAttribute でハイライト（ドキュメント非破壊）
private struct EditorObserver: NSViewRepresentable {
    @Binding var scrollRatio: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            context.coordinator.attach(to: view, scrollRatio: $scrollRatio)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var scrollObserver: Any?
        private var selectionObserver: Any?
        private var lastHighlightedRange: NSRange = NSRange(location: NSNotFound, length: 0)

        /// 淡いウォームグレー — kobaPaper(#FDFBF5) より少し暗い
        private static let highlightColor = NSColor(srgbRed: 0.918, green: 0.910, blue: 0.890, alpha: 1)

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
        }

        // MARK: - Scroll

        private func subscribeScroll(_ sv: NSScrollView, ratio: Binding<Double>) {
            sv.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: sv.contentView,
                queue: .main
            ) { [weak sv] _ in
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
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: tv,
                queue: .main
            ) { [weak self, weak tv] _ in
                guard let self, let tv else { return }
                self.highlightCurrentLine(in: tv)
            }
            highlightCurrentLine(in: tv)
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

            lm.addTemporaryAttribute(.backgroundColor, value: Self.highlightColor, forCharacterRange: lineRange)
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
            [scrollObserver, selectionObserver].compactMap { $0 }.forEach {
                NotificationCenter.default.removeObserver($0)
            }
        }
    }
}
