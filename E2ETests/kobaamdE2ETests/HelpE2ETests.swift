import XCTest

final class HelpE2ETests: E2ETestBase {
    func testHelpWindow() {
        navigateToMenu(menu: "ヘルプ", item: "kobaamd ヘルプ")

        let helpWindow = app.windows["kobaamd ヘルプ"]
        XCTAssertTrue(helpWindow.waitForExistence(timeout: 5), "Help window did not appear.")
        helpWindow.click()

        takeScreenshot(name: "help_window")
    }
}
