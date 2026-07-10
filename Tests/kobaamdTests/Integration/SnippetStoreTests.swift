import Testing
@testable import kobaamd
import Foundation

@Suite("SnippetStore")
@MainActor
struct SnippetStoreTests {
    private var suiteName: String
    private var defaults: UserDefaults

    init() throws {
        suiteName = "kobaamd.snippetstore.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("デフォルトスニペットは 5 件")
    func defaultSnippetsCount() {
        let store = SnippetStore(defaults: defaults)
        #expect(store.snippets.filter(\.isDefault).count == 5)
    }

    @Test("query が空のとき全件返す")
    func filterEmpty() {
        let store = SnippetStore(defaults: defaults)
        #expect(store.filter(query: "").count == store.snippets.count)
    }

    @Test("query=要約 で 1 件だけマッチ")
    func filterMatch() {
        let store = SnippetStore(defaults: defaults)
        #expect(store.filter(query: "要約").count == 1)
    }

    @Test("query=xyz で 0 件")
    func filterNoMatch() {
        let store = SnippetStore(defaults: defaults)
        #expect(store.filter(query: "xyz").count == 0)
    }

    @Test("addCustom でスニペット数が 1 増える")
    func addCustom() {
        let store = SnippetStore(defaults: defaults)
        let before = store.snippets.count
        store.addCustom(title: "校正", prompt: "この文章を校正して")
        #expect(store.snippets.count == before + 1)
    }

    @Test("removeCustom でスニペット数が 1 減る")
    func removeCustom() {
        let store = SnippetStore(defaults: defaults)
        store.addCustom(title: "校正", prompt: "この文章を校正して")
        let before = store.snippets.count
        guard let id = store.customSnippets.first?.id else {
            Issue.record("カスタムスニペットが追加されていない")
            return
        }
        store.removeCustom(id: id)
        #expect(store.snippets.count == before - 1)
    }

    @Test("addCustom 後に再読み込みしても同じカスタムが存在する")
    func persistence() {
        let store = SnippetStore(defaults: defaults)
        store.addCustom(title: "校正", prompt: "この文章を校正して")

        let reloaded = SnippetStore(defaults: defaults)
        #expect(reloaded.customSnippets.contains {
            $0.title == "校正" && $0.prompt == "この文章を校正して"
        })
    }
}
