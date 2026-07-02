import Foundation
import Testing
@testable import kobaamd

@Suite("EditorTab")
struct EditorTabTests {

    @Test("url なしで title が Untitled になること")
    func titleDefaultsToUntitled() {
        let tab = EditorTab()
        #expect(tab.title == "Untitled")
    }

    @Test("url ありで title がファイル名になること")
    func titleReflectsURLLastPathComponent() {
        let url = URL(fileURLWithPath: "/path/to/File.md")
        var tab = EditorTab()
        tab.url = url
        #expect(tab.title == "File.md")
    }

    @Test("デフォルト init で isDirty = false")
    func defaultTabIsNotDirty() {
        let tab = EditorTab()
        #expect(tab.isDirty == false)
    }

    @Test("content の変更が反映されること")
    func contentUpdatesReflect() {
        var tab = EditorTab()
        tab.content = "Hello"
        #expect(tab.content == "Hello")
    }

    @Test("2つの EditorTab は別々の UUID を持つこと")
    func tabsHaveUniqueIDs() {
        let first = EditorTab()
        let second = EditorTab()
        #expect(first.id != second.id)
    }

    @Test("全フィールドが同じコピーは等しいこと")
    func copyIsEqual() {
        let original = EditorTab(content: "Sample")
        let copy = original
        #expect(original == copy)
    }
}
