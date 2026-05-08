import Foundation

protocol BacklinkContextCheckerProtocol: Sendable {
    func judge(sourceContent: String, snippet: String, targetBasename: String) async -> BacklinkContextCache.Verdict?
}

final class BacklinkContextChecker: BacklinkContextCheckerProtocol, @unchecked Sendable {
    func judge(
        sourceContent: String,
        snippet: String,
        targetBasename: String
    ) async -> BacklinkContextCache.Verdict? {
        guard let key = APIKeyStore.load(for: .anthropic), !key.isEmpty else {
            return nil
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let sourcePrefix = String(sourceContent.prefix(200))
        let systemPrompt = """
        You judge whether a mention in a source markdown document refers to a specific target document. Reply with exactly one word: YES or NO. Then on the next line, give a one-line reason (max 80 chars).
        """
        let contextPrompt = """
        Source document title context (first 200 chars):
        \(sourcePrefix)
        """
        let questionPrompt = """
        Mention snippet (the word in question is between <<< and >>>):
        \(snippet)

        Target document title (basename, no extension): \(targetBasename)

        Question: Is the mention referring to the document titled "\(targetBasename)"?
        """

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 64,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt
                ]
            ],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": contextPrompt,
                            "cache_control": ["type": "ephemeral"]
                        ],
                        [
                            "type": "text",
                            "text": questionPrompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
            guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
                return nil
            }

            let firstLine = text
                .components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch firstLine {
            case "yes":
                return .yes
            case "no":
                return .no
            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

private struct AnthropicMessageResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}
