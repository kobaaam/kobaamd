import Testing
@testable import kobaamd

@Suite("E1AgentStatusParser")
struct E1AgentStatusParserTests {
    @Test("plain shell is unknown")
    func plainShell() {
        let text = """
        Last login: Fri Jun 12 09:00:00 on ttys001
        ~ %
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .unknown)
    }

    @Test("claude working via esc to interrupt")
    func claudeWorking() {
        let text = """
        Claude Code v1.0
        Working on src/foo.swift
        esc to interrupt
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .working)
    }

    @Test("claude blocked on permission question")
    func claudeBlocked() {
        let text = """
        Claude Code
        Do you want to proceed with this edit?
        ❯ 1. Yes
          2. No
        esc to cancel
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .blocked)
    }

    @Test("claude idle at prompt")
    func claudeIdle() {
        let text = """
        Claude Code
        bypass permissions on (shift+tab to cycle)
        ❯
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .idle)
    }

    @Test("done phrase when agent context present")
    func claudeDone() {
        let text = """
        Claude Code
        Task complete — review the diff above.
        """
        #expect(E1AgentStatusParser.parse(viewportText: text) == .done)
    }
}