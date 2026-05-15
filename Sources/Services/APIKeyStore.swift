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

    /// Production Keychain service identifier.
    private static let productionService = "com.kobaamd.apikeys"

    /// Overridable service identifier. Tests set this to a test-only value
    /// so they never touch the production Keychain.
    ///
    /// `nonisolated(unsafe)` is safe here because mutations only happen
    /// at test setUp, before any concurrent access begins.
    nonisolated(unsafe) static var serviceOverride: String? = nil

    private static var service: String {
        serviceOverride ?? productionService
    }

    // MARK: - In-process cache (KMD-187)
    //
    // `SecItemCopyMatching` is expensive on ad-hoc signed + Hardened Runtime
    // builds (one lookup triggers 400+ securityd DB queries). Repeated calls
    // from the main thread (e.g. BacklinksViewModel.refresh on every file
    // switch / scroll) cause noticeable hitches. Cache results in-process so
    // only the first lookup hits the keychain.
    //
    // `String??` (i.e. `Optional<String?>`) is intentional: the *outer*
    // Optional means "is the entry present in the cache?" while the *inner*
    // Optional means "did the lookup return a value?". This lets us cache a
    // negative result (no key set) so subsequent loads return `nil` without
    // touching the keychain.
    private static var cache: [Provider: String?] = [:]
    private static let cacheLock = NSLock()

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

        cacheLock.lock()
        cache[provider] = .some(key)
        cacheLock.unlock()
    }

    static func load(for provider: Provider) -> String? {
        // Cache fast-path. Hit on `.some(...)` (including `.some(nil)`) means
        // we already resolved this provider in-process and can skip the
        // expensive keychain query.
        cacheLock.lock()
        let cached = cache[provider]
        cacheLock.unlock()
        if let cached {
            return cached
        }

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
            cacheLock.lock()
            cache[provider] = .some(str)
            cacheLock.unlock()
            return str
        }

        // 2. Migrate from legacy UserDefaults store
        if let legacy = UserDefaults.standard.string(forKey: "apiKey_\(provider.rawValue)"),
           !legacy.isEmpty {
            save(legacy, for: provider)   // move to Keychain (also updates cache)
            return legacy
        }

        // 3. Fallback to environment variable (development)
        let envVal = ProcessInfo.processInfo.environment[provider.envKey]
        let value = envVal.flatMap { $0.isEmpty ? nil : $0 }

        cacheLock.lock()
        cache[provider] = .some(value)
        cacheLock.unlock()

        return value
    }

    static func clear(for provider: Provider) {
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "apiKey_\(provider.rawValue)")

        // Cache the cleared state so the next `load` does not re-query the
        // keychain for a known-missing entry.
        cacheLock.lock()
        cache[provider] = .some(nil)
        cacheLock.unlock()
    }

    /// Drops the cached entry for `provider` so the next `load` re-fetches
    /// from keychain / UserDefaults / env. Use this after external mutations
    /// outside the normal `save`/`clear` paths.
    static func invalidate(for provider: Provider) {
        cacheLock.lock()
        cache.removeValue(forKey: provider)
        cacheLock.unlock()
    }

    /// Drops every cached entry. Primarily for tests.
    static func invalidateAll() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
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
