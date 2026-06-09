import AppKit

enum WindowChrome {
    static func configureE1Window(_ window: NSWindow) {
        guard AppState.shared.useE1Shell else { return }

        let theme = AppState.shared.selectedTheme
        let title = "kobaamd (E1) \(AppVersion.bundleMarketing)"

        window.title = title
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = theme.chromeTitlebarNSColor
        window.appearance = NSAppearance(named: theme.prefersDarkChrome ? .darkAqua : .aqua)

        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }

        restoreTrafficLightButtons(in: window)
        scheduleTitlebarIconHiding(for: window)
    }

    static func scheduleTitlebarIconHiding(for window: NSWindow) {
        for delay in [0.0, 0.1, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                restoreTrafficLightButtons(in: window)
                hideTitlebarDocumentIcon(in: window)
            }
        }
    }

    /// 過去の広すぎる非表示処理で隠れた 3 色ボタンを必ず復元する。
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

    static func hideTitlebarDocumentIcon(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let trafficContainer = close.superview,
              let titlebar = trafficContainer.superview ?? zoom.superview else { return }

        let trafficMaxX = trafficContainer.frame.maxX

        for subview in titlebar.subviews {
            guard !containsStandardWindowButton(subview) else { continue }

            let name = String(describing: type(of: subview))
            if name.contains("Title") || name.contains("Text") || name.contains("Toolbar") {
                continue
            }

            let isDocumentIconSlot = subview.frame.minX >= trafficMaxX - 4
                && subview.frame.width <= 28
                && subview.frame.height <= 28
                && name.contains("Icon")

            if isDocumentIconSlot {
                subview.isHidden = true
            }
        }
    }

    private static func containsStandardWindowButton(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let node = current {
            if node is NSButton, node.window?.standardWindowButton(.closeButton) === node
                || node.window?.standardWindowButton(.miniaturizeButton) === node
                || node.window?.standardWindowButton(.zoomButton) === node {
                return true
            }
            current = node.superview
        }
        for child in view.subviews where containsStandardWindowButton(child) {
            return true
        }
        return false
    }
}