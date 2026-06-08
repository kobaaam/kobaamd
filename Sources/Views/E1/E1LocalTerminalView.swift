import AppKit
import Foundation
import SwiftTerm

// MARK: - E1 terminal tuned for Claude Code (keyboard, paste, selection stability)

final class E1LocalTerminalView: LocalProcessTerminalView {
    var pasteImageDirectory: URL?
    private var keyMonitor: Any?

    override init(frame: CGRect) {
        super.init(frame: frame)
        optionAsMetaKey = true
        enableClaudeCodeKeyboard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        optionAsMetaKey = true
        enableClaudeCodeKeyboard()
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

    /// Kitty keyboard protocol — Shift+Enter と修飾キーを Claude Code が識別できるようにする。
    func enableClaudeCodeKeyboard() {
        feed(text: "\u{1b}[>1u")
    }

    override func paste(_ sender: Any) {
        if handleImagePaste(insertPath: true) { return }
        super.paste(sender)
    }

    private func installKeyMonitorIfNeeded() {
        guard window != nil, keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.firstResponder === self else { return event }
            if self.handleShiftEnter(event) { return nil }
            if self.handleOptionVImagePaste(event) { return nil }
            return event
        }
    }

    private func handleShiftEnter(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36, event.modifierFlags.contains(.shift) else { return false }
        guard terminal.keyboardEnhancementFlags.isEmpty else { return false }
        send(txt: "\n")
        return true
    }

    private func handleOptionVImagePaste(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.option),
              event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
        return handleImagePaste(insertPath: false)
    }

    /// 画像を一意ファイル名で保存し、Claude Code の Alt+V（⌥V）またはパス貼り付けで渡す。
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
            insertText(savedPath, replacementRange: NSRange(location: 0, length: 0))
        } else {
            send(txt: "\u{1b}v")
        }
        return true
    }
}

enum E1TerminalTypography {
    static let defaultSize: CGFloat = 14
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