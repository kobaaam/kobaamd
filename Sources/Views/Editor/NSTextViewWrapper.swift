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

/// TextEditor の親 NSScrollView を検出してスクロール比率を binding に流す。
/// サイズゼロの透明 NSView を background に置くだけで、描画への影響はない。
private struct ScrollRatioReader: NSViewRepresentable {
    @Binding var ratio: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        // ビュー階層が構築されてから NSScrollView を探す
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
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
            // 親ビュー階層を辿って NSScrollView を見つける
            var current: NSView? = view.superview
            while let v = current {
                if let sv = v as? NSScrollView {
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
                    return
                }
                current = v.superview
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
