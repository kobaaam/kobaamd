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

    @Test("markdown の既定モードは分割")
    func markdownDefaultModeIsSplit() {
        #expect(E1ViewerLayoutPolicy.defaultMarkdownMode(for: .markdown) == .split)
        #expect(E1ViewerLayoutPolicy.defaultMarkdownMode(for: .d2) == .editor)
    }

    @Test("d2 / csv は専用タブが既定")
    func specializedDefaultTabs() {
        #expect(E1ViewerLayoutPolicy.defaultTab(for: URL(fileURLWithPath: "/a.d2")) == .d2)
        #expect(E1ViewerLayoutPolicy.defaultTab(for: URL(fileURLWithPath: "/b.csv")) == .csv)
    }

    @Test("Split は markdown + split モードのときのみ")
    func markdownSplitGate() {
        #expect(
            E1ViewerLayoutPolicy.usesMarkdownSplit(
                kind: .markdown, mode: .split
            )
        )
        #expect(
            !E1ViewerLayoutPolicy.usesMarkdownSplit(
                kind: .csv, mode: .split
            )
        )
        #expect(
            !E1ViewerLayoutPolicy.usesMarkdownSplit(
                kind: .markdown, mode: .editor
            )
        )
    }
}