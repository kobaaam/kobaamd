import AppKit
import Foundation
import GhosttyTerminal

@MainActor
enum E1TerminalEngine {
    /// Ghostty scrollback cap per surface (RAM). 古い行は `.kobaamd/transcript.log` へ。
    static let scrollbackLimit = E1TerminalMemoryPolicy.scrollbackLimit

    private static var _sharedController: TerminalController?

    static var sharedController: TerminalController {
        if let _sharedController { return _sharedController }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let term = E1TerminalTermConfig.shellTermName
        let controller = TerminalController { builder in
            applyBaseConfiguration(to: &builder, shell: shell, term: term)
        }
        _sharedController = controller
        return controller
    }

    private static func applyBaseConfiguration(
        to builder: inout TerminalConfiguration.Builder,
        shell: String,
        term: String
    ) {
        builder.withBackgroundOpacity(1)
        builder.withCustom("scrollback-limit", scrollbackLimit)
        builder.withCustom("command", "\(shell) -l")
        builder.withCustom("env", "TERM=\(term)")
        builder.withCustom("keybind", "shift+enter=text:\\x1b[13;2u")
        builder.withWindowPaddingX(0)
        builder.withWindowPaddingY(0)
    }

    static func applyAppearance(theme: ColorTheme = AppState.shared.selectedTheme) {
        let size = Float(AppState.shared.terminalFontSize)
        let scheme = TerminalTheme(
            light: appearanceConfiguration(theme: theme, fontSize: size),
            dark: appearanceConfiguration(theme: theme, fontSize: size)
        )
        _ = sharedController.setTheme(scheme)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let term = E1TerminalTermConfig.shellTermName
        _ = sharedController.setTerminalConfiguration(
            TerminalConfiguration { builder in
                applyBaseConfiguration(to: &builder, shell: shell, term: term)
                builder.withFontSize(size)
            }
        )
    }

    static func surfaceOptions(for session: WorktreeSession) -> TerminalSurfaceOptions {
        TerminalSurfaceOptions(
            backend: .exec,
            fontSize: Float(AppState.shared.terminalFontSize),
            workingDirectory: session.worktreePath.path
        )
    }

    private static func appearanceConfiguration(theme: ColorTheme, fontSize: Float) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withFontSize(fontSize)
            builder.withFontFamily("SF Mono")
            builder.withBackground(theme.editorBackground.ghosttyHexRGB)
            builder.withForeground(theme.terminalForeground.ghosttyHexRGB)
            for (index, color) in theme.terminalAnsiPalette.enumerated() {
                builder.withPalette(index, color: color.ghosttyHexRGB)
            }
        }
    }
}

private extension NSColor {
    var ghosttyHexRGB: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}