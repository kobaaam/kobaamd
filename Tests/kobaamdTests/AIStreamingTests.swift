import Testing
@testable import kobaamd

// MARK: - Mock

final class MockAIService: AIServiceProtocol, @unchecked Sendable {
    var tokensToEmit: [String] = []
    var errorToThrow: Error? = nil

    func complete(prompt: String, context: String, provider: APIKeyStore.Provider) async throws -> String {
        tokensToEmit.joined()
    }

    func stream(prompt: String, context: String, provider: APIKeyStore.Provider) -> AsyncThrowingStream<String, Error> {
        let tokens = tokensToEmit
        let error = errorToThrow
        return AsyncThrowingStream { continuation in
            Task {
                for token in tokens {
                    continuation.yield(token)
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - Tests

@Suite("AI Streaming Tests")
@MainActor
struct AIStreamingTests {

    @Test("トークンが順次 editorText に反映される")
    func streamingTokensAppendToEditorText() async throws {
        let mock = MockAIService()
        mock.tokensToEmit = ["Hello", ", ", "World"]
        let vm = AppViewModel(aiService: mock)
        vm.editorText = "{{テスト}}\n"

        vm.startAIInlineCompletion(lineContent: "{{テスト}}")

        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.editorText.contains("Hello, World"))
        #expect(!vm.editorText.contains("kobaamd-ai-generating"))
        #expect(vm.isAIGenerating == false)
    }

    @Test("ストリーミング途中のエラーでエラーメッセージが表示される")
    func streamingErrorShowsErrorMessage() async throws {
        let mock = MockAIService()
        mock.tokensToEmit = ["Partial"]
        mock.errorToThrow = AIError.invalidResponse
        let vm = AppViewModel(aiService: mock)
        vm.editorText = "{{テスト}}\n"

        vm.startAIInlineCompletion(lineContent: "{{テスト}}")

        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.editorText.contains("AI エラー"))
        #expect(vm.isAIGenerating == false)
    }
}
