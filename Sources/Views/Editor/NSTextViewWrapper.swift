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
                    ScrollRatioReader(ratio: $scrollRatio)
                }
            )
            .padding(.horizontal, 4)
    }
}

// MARK: - Scroll position observer

/// TextEditor の NSScrollView を検出してスクロール比率を binding に流す。
///
/// TextEditor の NSScrollView は background NSView の「兄弟」であり祖先ではないため、
/// 親を辿りながら各レベルで再帰的に下方向へ探索する。
private struct ScrollRatioReader: NSViewRepresentable {
    @Binding var ratio: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        // 0.2s 待ってビュー階層が構築されてから探索
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            context.coordinator.attach(to: view, ratio: $ratio)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var observer: Any?

        func attach(to view: NSView, ratio: Binding<Double>) {
            guard observer == nil else { return }

            // 親を辿りながら各レベルの兄弟サブツリーを再帰探索
            var current: NSView? = view
            for _ in 0..<25 {
                guard let parent = current?.superview else { break }
                if let sv = findTextScrollView(in: parent, excluding: current) {
                    subscribe(to: sv, ratio: ratio)
                    return
                }
                current = parent
            }
        }

        /// root 配下を再帰探索して NSTextView を documentView に持つ NSScrollView を返す。
        /// excluding で指定した NSView のブランチはスキップ（無限ループ防止）。
        private func findTextScrollView(in root: NSView, excluding: NSView?) -> NSScrollView? {
            for subview in root.subviews {
                if let excl = excluding, subview === excl { continue }
                if let sv = subview as? NSScrollView, sv.documentView is NSTextView {
                    return sv
                }
                if let found = findTextScrollView(in: subview, excluding: nil) {
                    return found
                }
            }
            return nil
        }

        private func subscribe(to sv: NSScrollView, ratio: Binding<Double>) {
            sv.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
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

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
