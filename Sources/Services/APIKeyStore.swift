import Foundation

/// Persists AI provider API keys in UserDefaults.
/// Phase 3 will migrate to Keychain for proper security.
final class APIKeyStore {
    private static let defaults = UserDefaults.standard

    enum Provider: String, CaseIterable {
        case openai    = "OpenAI (GPT-4o)"
        case anthropic = "Anthropic (Claude)"

        var defaultsKey: String { "apiKey_\(rawValue)" }
    }

    static func save(_ key: String, for provider: Provider) {
        defaults.set(key, forKey: provider.defaultsKey)
    }

    static func load(for provider: Provider) -> String? {
        let stored = defaults.string(forKey: provider.defaultsKey)
        // Fallback to environment variable for development convenience
        if stored == nil || stored!.isEmpty {
            let envKey: String
            switch provider {
            case .openai:    envKey = "OPENAI_API_KEY"
            case .anthropic: envKey = "ANTHROPIC_API_KEY"
            }
            return ProcessInfo.processInfo.environment[envKey]
        }
        return stored
    }

    static func clear(for provider: Provider) {
        defaults.removeObject(forKey: provider.defaultsKey)
    }
}
