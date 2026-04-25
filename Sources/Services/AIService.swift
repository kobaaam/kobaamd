import Foundation

enum AIError: LocalizedError {
    case noAPIKey(provider: String)
    case apiError(provider: String, statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .noAPIKey(p):
            return "\(p) の API キーが設定されていません。設定（⌘,）から登録してください。"
        case let .apiError(p, code, msg):
            return "\(p) API エラー (\(code)): \(msg)"
        case .invalidResponse:
            return "AI からの応答を解析できませんでした。"
        }
    }
}

final class AIService {
    // MARK: - Public API

    func complete(prompt: String, context: String, provider: APIKeyStore.Provider) async throws -> String {
        switch provider {
        case .openai:    return try await openAI(prompt: prompt, context: context)
        case .anthropic: return try await anthropic(prompt: prompt, context: context)
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

    // MARK: - System prompt

    private let systemPrompt = """
    You are a Markdown writing assistant embedded in kobaamd, a Mac-native Markdown editor.
    - Reply ONLY with Markdown text (no preamble, no explanation)
    - Preserve the original language of the user's text
    - Keep formatting clean and consistent
    """
}
