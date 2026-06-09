import Testing
@testable import kobaamd

@Suite("E1TerminalKeyboardSupport")
struct E1TerminalKeyboardTests {
    @Test("shiftEnter uses kitty CSI u for Return + Shift")
    func shiftEnterSequence() {
        #expect(E1TerminalKeyboardSupport.shiftEnter == "\u{1b}[13;2u")
    }

}