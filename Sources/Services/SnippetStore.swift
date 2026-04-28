import Foundation
import Observation

@MainActor
@Observable
final class SnippetStore {
    struct Snippet: Identifiable, Codable, Equatable {
        let id: UUID
        var title: String
        var prompt: String
        var isDefault: Bool
    }

    private static let storageKey = "kobaamd.snippets.custom"

    private static let defaultSnippets: [Snippet] = [
        .init(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "この段落を要約して",
            prompt: "この段落を要約して",
            isDefault: true
        ),
        .init(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "箇条書きに変換して",
            prompt: "箇条書きに変換して",
            isDefault: true
        ),
        .init(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "英語に翻訳して",
            prompt: "英語に翻訳して",
            isDefault: true
        ),
        .init(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            title: "続きを3段落書いて",
            prompt: "続きを3段落書いて",
            isDefault: true
        ),
        .init(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            title: "見出し構造を提案して",
            prompt: "見出し構造を提案して",
            isDefault: true
        )
    ]

    private let defaults: UserDefaults
    private(set) var customSnippets: [Snippet] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadCustomSnippets()
    }

    var snippets: [Snippet] {
        Self.defaultSnippets + customSnippets
    }

    func filter(query: String) -> [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snippets }
        return snippets.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    func addCustom(title: String, prompt: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedPrompt.isEmpty else { return }

        customSnippets.append(
            Snippet(
                id: UUID(),
                title: trimmedTitle,
                prompt: trimmedPrompt,
                isDefault: false
            )
        )
        persistCustomSnippets()
    }

    func removeCustom(id: UUID) {
        customSnippets.removeAll { $0.id == id }
        persistCustomSnippets()
    }

    private func loadCustomSnippets() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else {
            customSnippets = []
            return
        }

        customSnippets = decoded.map {
            Snippet(id: $0.id, title: $0.title, prompt: $0.prompt, isDefault: false)
        }
    }

    private func persistCustomSnippets() {
        if customSnippets.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }

        let payload = customSnippets.map {
            Snippet(id: $0.id, title: $0.title, prompt: $0.prompt, isDefault: false)
        }

        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
