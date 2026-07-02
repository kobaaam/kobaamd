import AppKit
import Foundation

@MainActor
final class ChromiumPreviewController {
    static let shared = ChromiumPreviewController()

    private var activeBrowser: ChromiumBrowser?
    private var previewIsOpen = false
    private var profileDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("kobaamd/ChromiumPreview", isDirectory: true)
    }

    private init() {}

    var installedBrowser: ChromiumBrowser? {
        ChromiumBrowserLocator.preferredBrowser()
    }

    func openOrNavigate(to previewURL: URL, in screenFrame: CGRect) {
        guard let browser = installedBrowser else { return }
        guard screenFrame.width > 1, screenFrame.height > 1 else { return }
        activeBrowser = browser
        if previewIsOpen {
            navigate(to: previewURL, in: screenFrame)
            return
        }
        previewIsOpen = true
        try? FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executableURL(for: browser)
        process.arguments = [
            "--app=\(previewURL.absoluteString)",
            "--user-data-dir=\(profileDirectory.path)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--disable-popup-blocking",
            "--disable-restore-session-state",
        ]
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.alignFrontWindow(of: browser, to: screenFrame)
        }
    }

    func reloadActivePage(in screenFrame: CGRect) {
        guard let browser = activeBrowser ?? installedBrowser else { return }
        runAppleScript(
            """
            tell application "\(browser.appName)"
                if (count of windows) > 0 then
                    reload active tab of front window
                end if
            end tell
            """
        )
        alignFrontWindow(of: browser, to: screenFrame)
    }

    func navigate(to previewURL: URL, in screenFrame: CGRect) {
        guard let browser = activeBrowser ?? installedBrowser else { return }
        activeBrowser = browser
        runAppleScript(
            """
            tell application "\(browser.appName)"
                activate
                if (count of windows) = 0 then
                    make new window
                end if
                set URL of active tab of front window to "\(escapeForAppleScript(previewURL.absoluteString))"
            end tell
            """
        )
        alignFrontWindow(of: browser, to: screenFrame)
    }

    func closePreviewWindow() {
        previewIsOpen = false
        guard let browser = activeBrowser ?? installedBrowser else { return }
        runAppleScript(
            """
            tell application "\(browser.appName)"
                if (count of windows) > 0 then
                    close front window
                end if
            end tell
            """
        )
    }

    func alignFrontWindow(of browser: ChromiumBrowser, to screenFrame: CGRect) {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }
        let left = Int(screenFrame.minX.rounded())
        let top = Int(screenFrame.minY.rounded())
        let right = Int(screenFrame.maxX.rounded())
        let bottom = Int(screenFrame.maxY.rounded())
        runAppleScript(
            """
            tell application "\(browser.appName)"
                activate
                if (count of windows) > 0 then
                    set bounds of front window to {\(left), \(top), \(right), \(bottom)}
                end if
            end tell
            """
        )
    }

    private func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    private func executableURL(for browser: ChromiumBrowser) -> URL {
        let plist = browser.bundleURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: plist),
           let name = dict["CFBundleExecutable"] as? String {
            return browser.bundleURL.appendingPathComponent("Contents/MacOS/\(name)")
        }
        return browser.bundleURL.appendingPathComponent("Contents/MacOS/\(browser.appName)")
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}