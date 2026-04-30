import Foundation
import XCTest

class E2ETestBase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication(bundleIdentifier: "com.kobaamd.app")

        switch app.state {
        case .notRunning:
            app.launch()
        case .runningBackground, .runningBackgroundSuspended:
            app.activate()
        default:
            break
        }

        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 3)
    }

    override func tearDown() {
        takeScreenshot(name: "\(currentTestName())_teardown")
        app = nil
        super.tearDown()
    }

    func takeScreenshot(name: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Expected at least one window before taking a screenshot.")

        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let fileManager = FileManager.default
        let screenshotDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("e2e_screenshots", isDirectory: true)

        do {
            try fileManager.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true, attributes: nil)
            let fileURL = screenshotDirectory.appendingPathComponent("\(sanitizedFileName(name)).png")
            try screenshot.pngRepresentation.write(to: fileURL)
        } catch {
            XCTFail("Failed to save screenshot '\(name)': \(error)")
        }
    }

    func navigateToMenu(menu: String, item: String) {
        let menuBarItem = app.menuBars.firstMatch.menuBarItems[menu]
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 5), "Menu '\(menu)' not found.")
        menuBarItem.click()

        let menuItem = app.menuBars.firstMatch.menuBarItems[menu].menus.menuItems[item]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "Menu item '\(item)' not found under '\(menu)'.")
        menuItem.click()
    }

    private func currentTestName() -> String {
        name
            .replacingOccurrences(of: "-[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func sanitizedFileName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
