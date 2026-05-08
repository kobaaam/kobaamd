import XCTest

final class EditorE2ETests: E2ETestBase {
    func testEditorInitialState() {
        takeScreenshot(name: "editor_initial")
    }

    func testEditorWithMarkdown() {
        navigateToMenu(menu: "ファイル", item: "新規")

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Editor text view did not appear.")
        editor.click()
        editor.typeText("# テスト見出し\n\nこれは E2E テストです。\n\n- リスト1\n- リスト2")

        Thread.sleep(forTimeInterval: 1)
        takeScreenshot(name: "editor_with_content")
    }

    func testSplitView() {
        navigateToMenu(menu: "表示", item: "スプリットビュー")
        takeScreenshot(name: "editor_split_view")
    }
}
