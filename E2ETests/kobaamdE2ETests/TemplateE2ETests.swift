import XCTest

final class TemplateE2ETests: E2ETestBase {
    func testTemplatePicker() {
        navigateToMenu(menu: "ファイル", item: "テンプレートから新規…")
        Thread.sleep(forTimeInterval: 2)

        takeScreenshot(name: "template_picker")

        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1)
    }
}
