import XCTest

final class SettingsE2ETests: E2ETestBase {
    func testSettingsWindow() {
        app.typeKey(",", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 2)

        takeScreenshot(name: "settings_window")

        app.typeKey("w", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1)
    }
}
