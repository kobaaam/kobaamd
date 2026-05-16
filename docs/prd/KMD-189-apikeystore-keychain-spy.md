---
linear: KMD-189
status: in-progress
created_at: 2026-05-16
author: Codex
---

# APIKeyStore Keychain spy cache verification

## 1. Background

KMD-187 added an in-process cache to `APIKeyStore`, but the existing tests only
asserted idempotent return values. They did not directly prove that a cache hit
skips the expensive `SecItemCopyMatching` path.

## 2. Goal

Introduce a narrow Keychain provider seam for `APIKeyStore` and use an in-memory
test double to count `SecItemCopyMatching`-equivalent calls.

## 3. Acceptance Criteria

- `APIKeyStore` production behavior still uses macOS Security framework calls.
- Tests can inject an in-memory Keychain provider without touching the
  production Keychain.
- A stored-key load performs exactly one copy-matching lookup before subsequent
  loads hit the cache.
- A missing-key load also performs exactly one copy-matching lookup before the
  negative or environment fallback result is cached.

## 4. Impact Scope

| File | Change | Notes |
|---|---|---|
| `Sources/Services/APIKeyStore.swift` | Add Keychain provider seam | Keep public save/load/clear API unchanged |
| `Tests/kobaamdTests/APIKeyStoreCacheTests.swift` | Add spy tests | Avoid printing or asserting secret values |
| `docs/prd/KMD-189-apikeystore-keychain-spy.md` | Add PRD-lite | Traceability for this carve-out |

Do not change settings UI, provider names, Keychain account names, or production
service identifiers.

## 5. Test Plan

- `swift build`
- `swift test`
