import Foundation
import Observation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    enum Role: String {
        case user = "user"
        case assistant = "assistant"
    }
}

@Observable
@MainActor
final class AIChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var selectedProvider: APIKeyStore.Provider = .openai
    var streamingContent: String = ""

    private let aiService: AIService
    private var activeTask: Task<Void, Never>? = nil
    private let maxMessages = 100

    init(aiService: AIService = AIService()) {
        self.aiService = aiService
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        appendMessage(role: .user, content: text)

        isLoading = true
        errorMessage = nil
        streamingContent = ""

        activeTask = Task { @MainActor in
            do {
                let contextMessages = Array(messages.suffix(20))
                let stream = aiService.streamChat(messages: contextMessages, provider: selectedProvider)
                var accumulated = ""
                for try await token in stream {
                    accumulated += token
                    streamingContent = accumulated
                }
                appendMessage(role: .assistant, content: accumulated)
                streamingContent = ""
            } catch is CancellationError {
                streamingContent = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func clearMessages() {
        messages = []
        streamingContent = ""
        errorMessage = nil
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
    }

    func appendMessage(role: ChatMessage.Role, content: String) {
        let msg = ChatMessage(id: UUID(), role: role, content: content, timestamp: Date())
        messages.append(msg)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }
}
