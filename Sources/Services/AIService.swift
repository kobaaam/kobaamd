import Foundation

// MARK: - Protocol

/// テスト時にモックを注入できるようにするためのプロトコル。
protocol AIServiceProtocol: AnyObject, Sendable {
    func complete(prompt: String, context: String, provider: APIKeyStore.Provider) async throws -> String
    func stream(prompt: String, context: String, provider: APIKeyStore.Provider) -> AsyncThrowingStream<String, Error>
    func streamChat(messages: [ChatMessage], provider: APIKeyStore.Provider) -> AsyncThrowingStream<String, Error>
}

extension AIServiceProtocol {
    func streamChat(messages: [ChatMessage], provider: APIKeyStore.Provider) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIError.noAPIKey(provider: provider.displayName))
        }
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case noAPIKey(provider: String)
    case apiError(provider: String, statusCode: Int, message: String)
    case streamError(provider: String, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .noAPIKey(p):
            return "\(p) の API キーが設定されていません。設定（⌘,）から登録してください。"
        case let .apiError(p, code, msg):
            return "\(p) API エラー (\(code)): \(msg)"
        case let .streamError(p, msg):
            return "\(p) ストリームエラー: \(msg)"
        case .invalidResponse:
            return "AI からの応答を解析できませんでした。"
        }
    }
}

final class AIService: AIServiceProtocol {
    // MARK: - Public API

    func complete(prompt: String, context: String, provider: APIKeyStore.Provider) async throws -> String {
        switch provider {
        case .openai:
            return try await openAI(prompt: prompt, context: context)
        case .anthropic:
            return try await anthropic(prompt: prompt, context: context)
        case .confluenceURL, .confluenceEmail, .confluenceToken:
            throw AIError.noAPIKey(provider: provider.displayName)
        }
    }

    // MARK: - Streaming API

    /// SSE ストリーミングでトークンを逐次 yield する。
    func stream(prompt: String, context: String, provider: APIKeyStore.Provider) -> AsyncThrowingStream<String, Error> {
        switch provider {
        case .openai:
            return openAIStream(prompt: prompt, context: context)
        case .anthropic:
            return anthropicStream(prompt: prompt, context: context)
        default:
            return AsyncThrowingStream { $0.finish(throwing: AIError.noAPIKey(provider: provider.rawValue)) }
        }
    }

    // MARK: - Multi-turn chat streaming API

    /// マルチターン会話履歴を渡してストリーミングする。
    func streamChat(messages: [ChatMessage], provider: APIKeyStore.Provider) -> AsyncThrowingStream<String, Error> {
        switch provider {
        case .openai:
            return openAIChatStream(messages: messages)
        case .anthropic:
            return anthropicChatStream(messages: messages)
        default:
            return AsyncThrowingStream { $0.finish(throwing: AIError.noAPIKey(provider: provider.rawValue)) }
        }
    }

    // MARK: - OpenAI

    private func openAI(prompt: String, context: String) async throws -> String {
        guard let key = APIKeyStore.load(for: .openai), !key.isEmpty else {
            throw AIError.noAPIKey(provider: "OpenAI")
        }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let userContent = context.isEmpty ? prompt : "\(prompt)\n\n---\n\(context)"
        let body: [String: Any] = [
            "model": "gpt-5.4",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userContent],
            ],
            "max_completion_tokens": 4096,
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
            throw AIError.apiError(provider: "OpenAI", statusCode: http.statusCode, message: msg)
        }

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices  = json["choices"] as? [[String: Any]],
              let message  = choices.first?["message"] as? [String: Any],
              let content  = message["content"] as? String else {
            throw AIError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI Streaming

    private func openAIStream(prompt: String, context: String) -> AsyncThrowingStream<String, Error> {
        guard let key = APIKeyStore.load(for: .openai), !key.isEmpty else {
            return failingStream(AIError.noAPIKey(provider: "OpenAI"))
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let userContent = context.isEmpty ? prompt : "\(prompt)\n\n---\n\(context)"
        let body: [String: Any] = [
            "model": "gpt-5.4",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userContent],
            ],
            "max_completion_tokens": 4096,
            "stream": true,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return failingStream(error)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else {
                        throw AIError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        let data = try await Self.collectData(from: bytes)
                        throw AIError.apiError(
                            provider: "OpenAI",
                            statusCode: http.statusCode,
                            message: Self.apiErrorMessage(from: data)
                        )
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        let data = Data(payload.utf8)
                        if let errorEnvelope = try? JSONDecoder().decode(OpenAIStreamErrorEnvelope.self, from: data) {
                            throw AIError.streamError(provider: "OpenAI", message: errorEnvelope.error.message)
                        }

                        if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                           let token = chunk.choices.first?.delta.content, !token.isEmpty {
                            continuation.yield(token)
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Anthropic

    private func anthropic(prompt: String, context: String) async throws -> String {
        guard let key = APIKeyStore.load(for: .anthropic), !key.isEmpty else {
            throw AIError.noAPIKey(provider: "Anthropic")
        }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let userContent = context.isEmpty ? prompt : "\(prompt)\n\n---\n\(context)"
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_completion_tokens": 4096,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userContent]],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key,                 forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",        forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
            throw AIError.apiError(provider: "Anthropic", statusCode: http.statusCode, message: msg)
        }

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content  = json["content"] as? [[String: Any]],
              let text     = content.first?["text"] as? String else {
            throw AIError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic Streaming

    private func anthropicStream(prompt: String, context: String) -> AsyncThrowingStream<String, Error> {
        guard let key = APIKeyStore.load(for: .anthropic), !key.isEmpty else {
            return failingStream(AIError.noAPIKey(provider: "Anthropic"))
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let userContent = context.isEmpty ? prompt : "\(prompt)\n\n---\n\(context)"
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userContent]],
            "stream": true,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return failingStream(error)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else {
                        throw AIError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        let data = try await Self.collectData(from: bytes)
                        throw AIError.apiError(
                            provider: "Anthropic",
                            statusCode: http.statusCode,
                            message: Self.apiErrorMessage(from: data)
                        )
                    }

                    var currentEvent: String?
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7))
                            if currentEvent == "message_stop" {
                                continuation.finish()
                                return
                            }
                            continue
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        let data = Data(payload.utf8)

                        switch currentEvent {
                        case "content_block_delta":
                            if let chunk = try? JSONDecoder().decode(AnthropicStreamChunk.self, from: data),
                               let token = chunk.delta.text, !token.isEmpty {
                                continuation.yield(token)
                            }
                        case "error":
                            if let errorEnvelope = try? JSONDecoder().decode(AnthropicStreamErrorEnvelope.self, from: data) {
                                throw AIError.streamError(provider: "Anthropic", message: errorEnvelope.error.message)
                            }
                            throw AIError.invalidResponse
                        default:
                            break
                        }

                        currentEvent = nil
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - System prompt

    private let systemPrompt = """
    You are a Markdown writing assistant embedded in kobaamd, a Mac-native Markdown editor.
    - Reply ONLY with Markdown text (no preamble, no explanation)
    - Preserve the original language of the user's text
    - Keep formatting clean and consistent
    """
}

// MARK: - SSE デコード用 private 型 / ユーティリティ

private extension AIService {
    // MARK: OpenAI multi-turn chat stream

    private func openAIChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        guard let key = APIKeyStore.load(for: .openai), !key.isEmpty else {
            return failingStream(AIError.noAPIKey(provider: "OpenAI"))
        }
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return failingStream(AIError.invalidResponse)
        }
        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
        ] + messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = [
            "model": "gpt-5.4",
            "messages": apiMessages,
            "max_completion_tokens": 4096,
            "stream": true,
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        guard let body = try? JSONSerialization.data(withJSONObject: body) else {
            return failingStream(AIError.invalidResponse)
        }
        req.httpBody = body

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw AIError.invalidResponse }
                    guard http.statusCode == 200 else {
                        let data = try await Self.collectData(from: bytes)
                        throw AIError.apiError(provider: "OpenAI", statusCode: http.statusCode, message: Self.apiErrorMessage(from: data))
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        let data = Data(payload.utf8)
                        if let errorEnvelope = try? JSONDecoder().decode(OpenAIStreamErrorEnvelope.self, from: data) {
                            throw AIError.streamError(provider: "OpenAI", message: errorEnvelope.error.message)
                        }
                        if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                           let token = chunk.choices.first?.delta.content, !token.isEmpty {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Anthropic multi-turn chat stream

    private func anthropicChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        guard let key = APIKeyStore.load(for: .anthropic), !key.isEmpty else {
            return failingStream(AIError.noAPIKey(provider: "Anthropic"))
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return failingStream(AIError.invalidResponse)
        }
        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": apiMessages,
            "stream": true,
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        guard let body = try? JSONSerialization.data(withJSONObject: body) else {
            return failingStream(AIError.invalidResponse)
        }
        req.httpBody = body

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw AIError.invalidResponse }
                    guard http.statusCode == 200 else {
                        let data = try await Self.collectData(from: bytes)
                        throw AIError.apiError(provider: "Anthropic", statusCode: http.statusCode, message: Self.apiErrorMessage(from: data))
                    }
                    var currentEvent: String?
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7))
                            if currentEvent == "message_stop" {
                                continuation.finish()
                                return
                            }
                            continue
                        }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        let data = Data(payload.utf8)
                        switch currentEvent {
                        case "content_block_delta":
                            if let chunk = try? JSONDecoder().decode(AnthropicStreamChunk.self, from: data),
                               let token = chunk.delta.text, !token.isEmpty {
                                continuation.yield(token)
                            }
                        case "error":
                            if let errorEnvelope = try? JSONDecoder().decode(AnthropicStreamErrorEnvelope.self, from: data) {
                                throw AIError.streamError(provider: "Anthropic", message: errorEnvelope.error.message)
                            }
                            throw AIError.invalidResponse
                        default:
                            break
                        }
                        currentEvent = nil
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: OpenAI

    struct OpenAIStreamChunk: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let delta: Delta
        }

        struct Delta: Decodable {
            let content: String?
        }
    }

    struct OpenAIStreamErrorEnvelope: Decodable {
        let error: StreamErrorPayload
    }

    // MARK: Anthropic

    struct AnthropicStreamChunk: Decodable {
        let delta: Delta

        struct Delta: Decodable {
            let text: String?
        }
    }

    struct AnthropicStreamErrorEnvelope: Decodable {
        let error: StreamErrorPayload
    }

    // MARK: 共通

    struct StreamErrorPayload: Decodable {
        let message: String
    }

    /// HTTPエラー時にバイトストリームを一括収集してエラーメッセージを取得する。
    static func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    static func apiErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = json["message"] as? String {
                return message
            }
        }
        return ""
    }

    /// エラーを即座に finish する AsyncThrowingStream を返すヘルパー。
    func failingStream(_ error: Error) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
