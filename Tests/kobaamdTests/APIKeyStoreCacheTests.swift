import Testing
@testable import kobaamd
import Foundation

/// KMD-187: verify that `APIKeyStore` caches lookups in-process and that the
/// public API contract (save/load/clear + invalidate) behaves as expected.
@Suite("APIKeyStoreCache", .serialized)
struct APIKeyStoreCacheTests {

    init() {
        // Redirect Keychain operations to a test-only service identifier so
        // this test suite never reads from or writes to the production Keychain.
        APIKeyStore.serviceOverride = "com.kobaamd.apikeys.tests"
        APIKeyStore.keychainProvider = SystemAPIKeyStoreKeychainProvider()
        APIKeyStore.invalidateAll()
    }

    /// Ensure each test starts from a clean state. We intentionally do this
    /// inline (rather than via shared setUp/tearDown) so the suite struct can
    /// stay value-typed under Swift Testing.
    private func reset(
        keychainProvider: APIKeyStoreKeychainProviding =
            SystemAPIKeyStoreKeychainProvider()
    ) {
        APIKeyStore.serviceOverride = "com.kobaamd.apikeys.tests"
        APIKeyStore.keychainProvider = keychainProvider
        APIKeyStore.invalidateAll()
        for p in APIKeyStore.Provider.allCases {
            APIKeyStore.clear(for: p)
        }
    }

    @Test("save then load returns the cached value")
    func saveThenLoadHitsCache() {
        reset()
        defer { reset() }

        APIKeyStore.save("test-key-1", for: .openai)

        let v1 = APIKeyStore.load(for: .openai)
        #expect(v1 == "test-key-1")

        // Second call should hit the in-process cache and return the same
        // value. We cannot directly assert "no SecItemCopyMatching call"
        // without mocking, but we at least exercise the hot path.
        let v2 = APIKeyStore.load(for: .openai)
        #expect(v2 == "test-key-1")
    }

    @Test("load is idempotent for missing keys")
    func loadCachesResultForMissingKey() {
        reset()
        defer { reset() }

        // Two consecutive loads should return the same result. Whether the
        // result is nil or an env-var fallback depends on the test
        // environment; we only assert idempotence.
        let v1 = APIKeyStore.load(for: .anthropic)
        let v2 = APIKeyStore.load(for: .anthropic)
        #expect(v1 == v2)
    }

    @Test("stored key cache hit skips repeated copyMatching")
    func storedKeyCacheHitSkipsRepeatedCopyMatching() {
        let keychain = CountingAPIKeyStoreKeychainProvider()
        reset(keychainProvider: keychain)
        defer { reset() }

        APIKeyStore.save("spy-key", for: .openai)
        APIKeyStore.invalidate(for: .openai)

        #expect(keychain.copyMatchingCallCount == 0)
        #expect(APIKeyStore.load(for: .openai) == "spy-key")
        #expect(keychain.copyMatchingCallCount == 1)
        #expect(APIKeyStore.load(for: .openai) == "spy-key")
        #expect(keychain.copyMatchingCallCount == 1)
    }

    @Test("missing key cache hit skips repeated copyMatching")
    func missingKeyCacheHitSkipsRepeatedCopyMatching() {
        let keychain = CountingAPIKeyStoreKeychainProvider()
        reset(keychainProvider: keychain)
        defer { reset() }

        APIKeyStore.invalidate(for: .anthropic)

        let first = APIKeyStore.load(for: .anthropic)
        #expect(keychain.copyMatchingCallCount == 1)
        let second = APIKeyStore.load(for: .anthropic)

        #expect(second == first)
        #expect(keychain.copyMatchingCallCount == 1)
    }

    @Test("clear invalidates the cached value")
    func clearInvalidatesCache() {
        reset()
        defer { reset() }

        APIKeyStore.save("temp", for: .openai)
        #expect(APIKeyStore.load(for: .openai) == "temp")

        APIKeyStore.clear(for: .openai)

        // After clear, the cached value must not still be "temp".
        let after = APIKeyStore.load(for: .openai)
        #expect(after != "temp")
    }

    @Test("invalidate forces a re-fetch from keychain")
    func invalidateForcesRefetch() {
        reset()
        defer { reset() }

        APIKeyStore.save("k1", for: .openai)
        #expect(APIKeyStore.load(for: .openai) == "k1")

        APIKeyStore.invalidate(for: .openai)

        // Keychain still holds "k1" so the next load re-fetches and returns
        // the original value.
        #expect(APIKeyStore.load(for: .openai) == "k1")
    }

    @Test("invalidateAll drops cache without touching keychain")
    func invalidateAllClearsCacheButNotKeychain() {
        reset()
        defer { reset() }

        APIKeyStore.save("k1", for: .openai)
        APIKeyStore.save("k2", for: .anthropic)

        APIKeyStore.invalidateAll()

        #expect(APIKeyStore.load(for: .openai) == "k1")
        #expect(APIKeyStore.load(for: .anthropic) == "k2")
    }

    @Test("concurrent loads are safe under NSLock")
    func concurrentLoadIsSafe() {
        reset()
        defer { reset() }

        APIKeyStore.save("concurrent", for: .openai)

        // `concurrentPerform` blocks until every iteration completes, so we
        // do not need an XCTest expectation. If the cache dictionary were
        // unprotected this would crash or trip TSAN.
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = APIKeyStore.load(for: .openai)
        }

        #expect(APIKeyStore.load(for: .openai) == "concurrent")
    }
}

private final class CountingAPIKeyStoreKeychainProvider:
    APIKeyStoreKeychainProviding {
    private var items: [String: Data] = [:]
    private(set) var copyMatchingCallCount = 0

    func update(
        _ query: [CFString: Any],
        attributes: [CFString: Any]
    ) -> OSStatus {
        guard let key = storageKey(for: query),
              let data = attributes[kSecValueData] as? Data else {
            return errSecParam
        }
        guard items[key] != nil else {
            return errSecItemNotFound
        }
        items[key] = data
        return errSecSuccess
    }

    func add(_ query: [CFString: Any]) -> OSStatus {
        guard let key = storageKey(for: query),
              let data = query[kSecValueData] as? Data else {
            return errSecParam
        }
        guard items[key] == nil else {
            return errSecDuplicateItem
        }
        items[key] = data
        return errSecSuccess
    }

    func copyMatching(
        _ query: [CFString: Any],
        result: inout AnyObject?
    ) -> OSStatus {
        copyMatchingCallCount += 1
        guard let key = storageKey(for: query) else {
            return errSecParam
        }
        guard let data = items[key] else {
            return errSecItemNotFound
        }
        result = data as NSData
        return errSecSuccess
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        guard let key = storageKey(for: query) else {
            return errSecParam
        }
        items.removeValue(forKey: key)
        return errSecSuccess
    }

    private func storageKey(for query: [CFString: Any]) -> String? {
        guard let service = query[kSecAttrService] as? String,
              let account = query[kSecAttrAccount] as? String else {
            return nil
        }
        return "\(service)\u{0}\(account)"
    }
}
