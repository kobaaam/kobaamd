import Foundation
import Testing
@testable import kobaamd

@Suite("E1ViewerLayoutPolicy")
struct E1ViewerLayoutPolicyTests {

    @Test("markdown は Rendered が既定")
    func markdownDefaultTab() {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        #expect(E1ViewerLayoutPolicy.fileKind(for: url) == .markdown)
        #expect(E1ViewerLayoutPolicy.defaultTab(for: url) == .rendered)
    }

    @Test("d2 / csv は専用タブが既定")
    func specializedDefaultTabs() {
        #expect(E1ViewerLayoutPolicy.defaultTab(for: URL(fileURLWithPath: "/a.d2")) == .d2)
        #expect(E1ViewerLayoutPolicy.defaultTab(for: URL(fileURLWithPath: "/b.csv")) == .csv)
    }

    @Test("Split は markdown + 有効 + Rendered/Source タブのときのみ")
    func markdownSplitGate() {
        #expect(
            E1ViewerLayoutPolicy.usesMarkdownSplit(
                kind: .markdown, splitEnabled: true, selectedTab: .rendered
            )
        )
        #expect(
            !E1ViewerLayoutPolicy.usesMarkdownSplit(
                kind: .csv, splitEnabled: true, selectedTab: .rendered
            )
        )
        #expect(
            !E1ViewerLayoutPolicy.usesMarkdownSplit(
                kind: .markdown, splitEnabled: false, selectedTab: .rendered
            )
        )
    }
}