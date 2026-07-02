import Testing
@testable import kobaamd
import AppKit
import Foundation

// MARK: - E1AgentStatus unit tests (pure enum properties)

@Suite("E1AgentStatus")
struct E1AgentStatusTests {

    // MARK: displayName

    @Test("displayName values are non-empty strings")
    func displayNamesAreNonEmpty() {
        let allCases: [E1AgentStatus] = [.blocked, .working, .done, .idle, .unknown]
        for status in allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    @Test("each status has a distinct displayName")
    func displayNamesAreDistinct() {
        let names = [E1AgentStatus.blocked, .working, .done, .idle, .unknown].map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    // MARK: indicatorColor

    @Test("indicatorColor values are in [0, 1]")
    func indicatorColorValuesAreInRange() {
        let allCases: [E1AgentStatus] = [.blocked, .working, .done, .idle, .unknown]
        for status in allCases {
            let c = status.indicatorColor
            #expect(c.red >= 0 && c.red <= 1)
            #expect(c.green >= 0 && c.green <= 1)
            #expect(c.blue >= 0 && c.blue <= 1)
        }
    }

    // MARK: showsIndicator

    @Test("unknown does not show indicator")
    func unknownDoesNotShowIndicator() {
        #expect(!E1AgentStatus.unknown.showsIndicator)
    }

    @Test("non-unknown statuses show indicator")
    func nonUnknownStatusesShowIndicator() {
        for status in [E1AgentStatus.blocked, .working, .done, .idle] {
            #expect(status.showsIndicator)
        }
    }
}

// MARK: - E1AgentStatusParser extended edge-case tests
//
// 基本ケースは Unit/E1AgentStatusParserTests.swift（5件）にある。
// ここでは既存テストで未カバーの分岐・境界ケースを追加する。

@Suite("E1AgentStatusParserEdgeCases")
struct E1AgentStatusParserEdgeCaseTests {

    @Test("Whitespace-only viewport returns unknown")
    func whitespaceViewportReturnsUnknown() {
        #expect(E1AgentStatusParser.parse(viewportText: "   \n\n\t") == .unknown)
    }

    @Test("Viewport with braille spinner returns working")
    func brailleSpinnerReturnsWorking() {
        let text = """
        Claude Code  bypass permissions
        ⠙ Processing request...
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .working)
    }

    @Test("Viewport with 'running tool' returns working")
    func runningToolReturnsWorking() {
        let text = """
        Claude Code  bypass permissions
        Running tool: Bash
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .working)
    }

    @Test("Viewport with 'thinking' returns working")
    func thinkingReturnsWorking() {
        let text = """
        Claude Code  bypass permissions
        Thinking...
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .working)
    }

    @Test("Viewport with 'y/n' returns blocked")
    func yNReturnsBlocked() {
        let text = """
        Claude Code  bypass permissions
        Overwrite existing file? (y/n)
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .blocked)
    }

    @Test("Viewport with numbered list returns blocked")
    func numberedListReturnsBlocked() {
        let text = """
        Claude Code  bypass permissions
        1. Option A
        2. Option B
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .blocked)
    }

    @Test("Viewport with 'all done' returns done")
    func allDoneReturnsDone() {
        let text = """
        Claude Code  bypass permissions
        All done — completed 3 tasks.
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .done)
    }

    @Test("Viewport ending with $ prompt returns idle")
    func dollarPromptReturnsIdle() {
        let text = """
        Claude Code  bypass permissions
        user@host $
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .idle)
    }

    @Test("CRLF line endings are normalized correctly")
    func crlfNormalization() {
        let text = "Claude Code  bypass permissions\r\nEsc to interrupt\r\n"
        #expect(E1AgentStatusParser.parse(viewportText: text) == .working)
    }

    @Test("Codex agent marker is recognized")
    func codexMarkerRecognized() {
        let text = """
        codex
        esc to interrupt
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .working)
    }
}

// MARK: - Regression guard: readViewportText / readScreenText compile check

/// 2026-06 に E1LocalTerminalView.readViewportText / readScreenText が未定義のまま
/// E1AgentStatusMonitor.refresh() から呼び出されコンパイルエラーになったリグレッションの再発防止。
///
/// このテストはメソッドシグネチャが E1LocalTerminalView に存在することを Swift 型システムで保証する。
/// コンパイルが通る = メソッドが定義されている = リグレッションなし。
@Suite("E1AgentStatus regression guard")
struct E1AgentStatusMonitorRegressionTests {
    @Test("E1LocalTerminalView has readViewportText and readScreenText (compile-time regression guard)")
    @MainActor
    func readMethodsExistOnE1LocalTerminalView() {
        // E1LocalTerminalView は AppKit ビューなのでインスタンスを生成せず、
        // メソッドのカリー化参照を取得することでコンパイル時に存在を確認する。
        let viewportRef: (E1LocalTerminalView) -> () -> String? = E1LocalTerminalView.readViewportText
        let screenRef: (E1LocalTerminalView) -> () -> String? = E1LocalTerminalView.readScreenText
        _ = viewportRef
        _ = screenRef
    }
}
