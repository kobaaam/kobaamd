import AppKit

enum WindowChrome {
    /// E1 のネイティブタイトルバーは常に macOS 標準のライト chrome にする。
    private static let e1TitlebarAppearance = NSAppearance(named: .aqua)
    private static let e1TitlebarBackground = ColorTheme.light.chromeTitlebarNSColor

    static func configureE1Window(_ window: NSWindow) {
        guard AppState.shared.useE1Shell else { return }

        let title = "kobaamd (E1) \(AppVersion.display)"

        window.title = title
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.backgroundColor = e1TitlebarBackground
        window.appearance = e1TitlebarAppearance

        if #available(macOS 11.0, *) {
            window.toolbarStyle = .automatic
        }

        restoreTrafficLightButtons(in: window)
        scheduleTrafficLightRestore(for: window)
    }

    private static func scheduleTrafficLightRestore(for window: NSWindow) {
        for delay in [0.05, 0.15, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard window === NSApp.keyWindow || NSApp.windows.contains(window) else { return }
                restoreTrafficLightButtons(in: window)
            }
        }
    }

    /// 3 色ボタンとその祖先を必ず表示する（カスタム chrome 後の復旧用）。
    static func restoreTrafficLightButtons(in window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap { $0 }

        for button in buttons {
            button.isHidden = false
            button.alphaValue = 1
            var ancestor: NSView? = button.superview
            while let view = ancestor {
                view.isHidden = false
                view.alphaValue = 1
                ancestor = view.superview
            }
        }
    }
}