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
        APIKeyStore.invalidateAll()
    }

    /// Ensure each test starts from a clean state. We intentionally do this
    /// inline (rather than via shared setUp/tearDown) so the suite struct can
    /// stay value-typed under Swift Testing.
    private func reset() {
        APIKeyStore.serviceOverride = "com.kobaamd.apikeys.tests"
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
