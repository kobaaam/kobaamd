import Foundation
import Testing
@testable import kobaamd

@Suite("AIChatViewModel")
@MainActor
struct AIChatViewModelTests {

    @Test("appendMessage でメッセージが追加されること")
    func appendMessageAddsToArray() {
        let vm = AIChatViewModel()
        vm.appendMessage(role: .user, content: "Hello")
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "Hello")
    }

    @Test("appendMessage でアシスタントメッセージが追加されること")
    func appendAssistantMessage() {
        let vm = AIChatViewModel()
        vm.appendMessage(role: .assistant, content: "Hi there")
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].role == .assistant)
    }

    @Test("100件を超えた場合に古いメッセージがトリムされること")
    func trimMessagesWhenExceedingLimit() {
        let vm = AIChatViewModel()
        for i in 0..<110 {
            vm.appendMessage(role: .user, content: "message \(i)")
        }
        #expect(vm.messages.count == 100)
        // 古いメッセージ（最初の10件）が削除され、最新100件が残ること
        #expect(vm.messages[0].content == "message 10")
        #expect(vm.messages[99].content == "message 109")
    }

    @Test("clearMessages で履歴がリセットされること")
    func clearMessagesResetsArray() {
        let vm = AIChatViewModel()
        vm.appendMessage(role: .user, content: "Hello")
        vm.appendMessage(role: .assistant, content: "Hi")
        vm.clearMessages()
        #expect(vm.messages.isEmpty)
    }

    @Test("ちょうど100件の場合はトリムされないこと")
    func exactlyAtLimitNoTrim() {
        let vm = AIChatViewModel()
        for i in 0..<100 {
            vm.appendMessage(role: .user, content: "message \(i)")
        }
        #expect(vm.messages.count == 100)
        #expect(vm.messages[0].content == "message 0")
    }
}
