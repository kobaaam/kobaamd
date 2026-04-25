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
    @Binding var scrollRatio: Double   // reserved — not yet exported

    private static let paperColor = Color(NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1))
    private static let inkColor   = Color(NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1))
    private static let editorFont = Font.system(size: 14, design: .monospaced)

    init(binding: Binding<String>, scrollRatio: Binding<Double>) {
        self._text        = binding
        self._scrollRatio = scrollRatio
    }

    var body: some View {
        ZStack {
            TextEditor(text: $text)
                .font(Self.editorFont)
                .foregroundStyle(Self.inkColor)
                .scrollContentBackground(.hidden)
                .background(Self.paperColor)
                .padding(.horizontal, 4)

            // 不可視の NSViewRepresentable — jumpToLine 通知を受け取り TextEditor 内の
            // NSTextView にアクセスしてカーソル移動・スクロールを行う
            JumpToLineHandler()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Jump to line handler

/// TextEditor 配下の NSTextView を探して jumpToLine 通知を受信し、
/// 対象行にカーソルを移動してスクロールさせる。
private struct JumpToLineHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var jumpObserver: Any?
        private weak var textViewRef: NSTextView?

        func attach(to view: NSView) {
            // TextEditor 配下の NSTextView を階層探索で取得
            var current: NSView? = view
            for _ in 0..<25 {
                guard let parent = current?.superview else { break }
                if let tv = findView(NSTextView.self, in: parent, excluding: current) {
                    textViewRef = tv
                    subscribeJumpToLine()
                    break
                }
                current = parent
            }
        }

        private func subscribeJumpToLine() {
            jumpObserver = NotificationCenter.default.addObserver(
                forName: .jumpToLine,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let line = notification.userInfo?["line"] as? Int else { return }
                self?.jumpToLine(line)
            }
        }

        private func jumpToLine(_ line: Int) {
            guard let tv = textViewRef else { return }

            let nsStr = tv.string as NSString
            let targetLine = max(1, line) - 1  // 0-indexed
            var currentLine = 0
            var charPos = 0

            while currentLine < targetLine && charPos < nsStr.length {
                let lineRange = nsStr.lineRange(for: NSRange(location: charPos, length: 0))
                charPos = NSMaxRange(lineRange)
                currentLine += 1
            }

            let range = NSRange(location: charPos, length: 0)
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(range)
            tv.scrollRangeToVisible(range)
        }

        /// 指定型の NSView をサブツリーから再帰探索する（excluding を除外）
        private func findView<T: NSView>(_ type: T.Type, in view: NSView, excluding: NSView?) -> T? {
            for subview in view.subviews {
                if subview === excluding { continue }
                if let found = subview as? T { return found }
                if let found = findView(type, in: subview, excluding: excluding) { return found }
            }
            return nil
        }

        deinit {
            if let jumpObserver {
                NotificationCenter.default.removeObserver(jumpObserver)
            }
        }
    }
}
