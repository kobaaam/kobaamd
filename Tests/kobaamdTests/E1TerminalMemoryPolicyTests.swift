import Testing
@testable import kobaamd

@Suite("E1 terminal memory policy")
struct E1TerminalMemoryPolicyTests {
    @Test("scrollback limit is configured for Ghostty")
    func scrollbackLimitIsBounded() {
        #expect(E1TerminalEngine.scrollbackLimit == "2m")
        #expect(E1TerminalMemoryPolicy.scrollbackLimit == "2m")
    }

    @Test("disk transcript limit is 100 MB")
    func diskTranscriptLimitIs100MB() {
        #expect(E1TerminalMemoryPolicy.diskTranscriptMaxBytes == 104_857_600)
    }
}