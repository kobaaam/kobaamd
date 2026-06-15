import AppKit
import Foundation
import GhosttyTerminal

// MARK: - E1 terminal (Ghostty) — Claude Code keyboard & image paste

final class E1LocalTerminalView: TerminalView {
    var pasteImageDirectory: URL?
    private var keyMonitor: Any?

    override init(frame: CGRect) {
        super.init(frame: frame)
        controller = E1TerminalEngine.sharedController
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installKeyMonitorIfNeeded()
    }

    private func installKeyMonitorIfNeeded() {
        guard window != nil, keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isReceivingKeyboardFocus else { return event }
            if self.handleImagePasteShortcut(event) { return nil }
            return event
        }
    }

    private var isReceivingKeyboardFocus: Bool {
        guard let window, let responder = window.firstResponder else { return false }
        if responder === self { return true }
        guard let view = responder as? NSView else { return false }
        return view.isDescendant(of: self)
    }

    private func handleImagePasteShortcut(_ event: NSEvent) -> Bool {
        guard event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option), !flags.contains(.command) {
            return handleImagePaste(insertPath: false)
        }
        if flags.contains(.command), !flags.contains(.option),
           E1TerminalPasteSupport.imageFromPasteboard(.general) != nil {
            return handleImagePaste(insertPath: true)
        }
        return false
    }

    @discardableResult
    func handleImagePaste(insertPath: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        guard let image = E1TerminalPasteSupport.imageFromPasteboard(pasteboard) else { return false }
        let directory = pasteImageDirectory ?? FileManager.default.temporaryDirectory
        guard let savedPath = E1TerminalPasteSupport.savePastedImage(image, directory: directory) else {
            return false
        }

        let fileURL = URL(fileURLWithPath: savedPath)
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])

        if insertPath {
            sendText(savedPath)
        } else {
            sendText("\u{1b}v")
        }
        return true
    }
}

enum E1TerminalKeyboardSupport {
    /// Shift+Enter — Claude Code / Ink が改行として扱うシーケンス（Ghostty keybind と同期）。
    static let shiftEnter = "\u{1b}[13;2u"
}

enum E1TerminalTypography {
    static let defaultSize: CGFloat = CGFloat(AppState.CodeFontSize.defaultSize)
    private static let fontCandidates = [
        "SFMono-Regular",
        "SF Mono",
        "Menlo-Regular",
        "Menlo",
        "Monaco",
    ]

    static func monospaceFont(size: CGFloat) -> NSFont {
        for name in fontCandidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }

    /// 丸数字などの記号を潰さないよう、等幅本体 + 記号フォントのカスケードを付ける。
    static func codeFont(size: CGFloat) -> NSFont {
        let base = monospaceFont(size: size)
        let cascades: [NSFontDescriptor] = [
            NSFontDescriptor(fontAttributes: [.family: "Apple Symbols"]),
            NSFontDescriptor(fontAttributes: [.family: "Hiragino Sans"]),
        ]
        let descriptor = base.fontDescriptor.addingAttributes([
            .cascadeList: cascades,
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

enum E1TerminalPasteSupport {
    static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
            return image
        }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
            return image
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], let url = urls.first,
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    static func savePastedImage(_ image: NSImage, directory: URL) -> String? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "paste-\(stamp)-\(UUID().uuidString.prefix(8)).png"
        let url = directory.appendingPathComponent(name)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        do {
            try png.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }
}