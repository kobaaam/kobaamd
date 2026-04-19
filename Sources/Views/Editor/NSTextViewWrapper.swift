import SwiftUI
import AppKit

struct NSTextViewWrapper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextView {
        NSTextView()
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {}
}
