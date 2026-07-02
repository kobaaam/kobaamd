import Testing
@testable import kobaamd
import AppKit
import Foundation

@Suite("E1TerminalPasteSupport")
struct E1TerminalPasteSupportTests {
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    var tmpDir: URL { workspace.root }

    @Test("Saved paste images get unique filenames")
    func savedPasteImagesAreUnique() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()

        let path1 = try #require(E1TerminalPasteSupport.savePastedImage(image, directory: tmpDir))
        let path2 = try #require(E1TerminalPasteSupport.savePastedImage(image, directory: tmpDir))
        #expect(path1 != path2)
        #expect(path1.hasSuffix(".png"))
        #expect(URL(fileURLWithPath: path1).lastPathComponent.hasPrefix("paste-"))
    }
}