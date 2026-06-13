import AppKit
import SwiftUI

/// E1 ウィンドウのネイティブタイトルバー（ライト chrome・3 色ボタン）を同期する。
struct E1WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = E1WindowChromeSyncView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window ?? NSApp.keyWindow else { return }
            WindowChrome.configureE1Window(window)
        }
    }
}

private final class E1WindowChromeSyncView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func layout() {
        super.layout()
        refresh()
    }

    private func refresh() {
        guard let window else { return }
        WindowChrome.configureE1Window(window)
    }
}