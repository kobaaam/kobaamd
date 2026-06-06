import XCTest

/// KMD-232: セッション A/B 切替で Files スコープが入替わる smoke。
/// 実行: `./scripts/run_e2e_tests.sh`（Tart VM + Xcode）
final class E1SessionSwitchE2ETests: E2ETestBase {
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.kobaamd.app")
        app.launchArguments.append("-E2ESessionFixture")
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 15)
        Thread.sleep(forTimeInterval: 3)
    }

    func testSessionSwitchUpdatesScopedFiles() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.title.contains("E1"), "Expected E1 shell window title, got: \(window.title)")

        let alphaRoot = app.staticTexts.matching(identifier: "e1.files.root").firstMatch
        XCTAssertTrue(alphaRoot.waitForExistence(timeout: 8), "Files root label missing for alpha session")
        XCTAssertEqual(alphaRoot.label, "alpha", "Expected alpha session root, got: \(alphaRoot.label)")
        takeScreenshot(name: "e1_session_alpha")

        let betaSession = app.buttons.matching(identifier: "e1.session.beta").firstMatch
        XCTAssertTrue(betaSession.waitForExistence(timeout: 8), "Beta session row not found")
        betaSession.click()
        Thread.sleep(forTimeInterval: 1)

        let betaRoot = app.staticTexts.matching(identifier: "e1.files.root").firstMatch
        XCTAssertTrue(betaRoot.waitForExistence(timeout: 8))
        XCTAssertEqual(betaRoot.label, "beta", "Expected beta session root after switch, got: \(betaRoot.label)")
        takeScreenshot(name: "e1_session_beta")
    }
}