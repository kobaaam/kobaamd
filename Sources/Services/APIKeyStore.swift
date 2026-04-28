import Foundation
import Security

/// Persists AI provider API keys in the macOS Keychain.
/// Falls back to environment variables for development convenience.
final class APIKeyStore {

    enum Provider: String, CaseIterable {
        case openai          = "openai"
        case anthropic       = "anthropic"
        case confluenceURL   = "confluenceURL"
        case confluenceEmail = "confluenceEmail"
        case confluenceToken = "confluenceToken"

        var displayName: String {
            switch self {
            case .openai:          return "OpenAI (GPT-5.4)"
            case .anthropic:       return "Anthropic (Claude)"
            case .confluenceURL:   return "Confluence Base URL"
            case .confluenceEmail: return "Confluence Email"
            case .confluenceToken: return "Confluence API Token"
            }
        }
        var isAIProvider: Bool {
            switch self {
            case .openai, .anthropic: return true
            case .confluenceURL, .confluenceEmail, .confluenceToken: return false
            }
        }
        var keychainAccount: String { rawValue }
        var envKey: String {
            switch self {
            case .openai:          return "OPENAI_API_KEY"
            case .anthropic:       return "ANTHROPIC_API_KEY"
            case .confluenceURL:   return "CONFLUENCE_URL"
            case .confluenceEmail: return "CONFLUENCE_EMAIL"
            case .confluenceToken: return "CONFLUENCE_TOKEN"
            }
        }
    }

    private static let service = "com.kobaamd.apikeys"

    // MARK: - Public API

    static func save(_ key: String, for provider: Provider) {
        guard !key.isEmpty else {
            clear(for: provider)
            return
        }
        let data = Data(key.utf8)
        let query = baseQuery(for: provider)

        // Update if exists, otherwise add
        let updateAttrs: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
        // Migrate away from UserDefaults if anything was stored there
        UserDefaults.standard.removeObject(forKey: "apiKey_\(provider.rawValue)")
    }

    static func load(for provider: Provider) -> String? {
        // 1. Try Keychain
        var query = baseQuery(for: provider)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }

        // 2. Migrate from legacy UserDefaults store
        if let legacy = UserDefaults.standard.string(forKey: "apiKey_\(provider.rawValue)"),
           !legacy.isEmpty {
            save(legacy, for: provider)   // move to Keychain
            return legacy
        }

        // 3. Fallback to environment variable (development)
        let envVal = ProcessInfo.processInfo.environment[provider.envKey]
        return envVal.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func clear(for provider: Provider) {
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "apiKey_\(provider.rawValue)")
    }

    // MARK: - Private

    private static func baseQuery(for provider: Provider) -> [CFString: Any] {
        [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.keychainAccount,
        ]
    }
}
