import AppKit
import Foundation

struct ChromiumBrowser: Equatable {
    let appName: String
    let bundleURL: URL

    var displayName: String { appName }
}

enum ChromiumBrowserLocator {
    private static let candidateBundleIDs = [
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac",
    ]

    static func preferredBrowser() -> ChromiumBrowser? {
        for bundleID in candidateBundleIDs {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                continue
            }
            let appName = FileManager.default.displayName(atPath: appURL.path)
            return ChromiumBrowser(appName: appName, bundleURL: appURL)
        }
        return nil
    }
}