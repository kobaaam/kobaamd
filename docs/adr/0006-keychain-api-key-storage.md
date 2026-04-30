# ADR-0006: macOS Keychain による API キー保存

- **Status**: accepted
- **Date**: 2026-02-01
- **Deciders**: 人間
- **Related**: ADR-0005

## Context

AI 機能で使用する API キーの永続化方式。セキュリティとユーザビリティのバランスが必要。

## Decision

**macOS Keychain** を主ストレージとし、開発用に環境変数フォールバックを持つ。レガシーの UserDefaults からの自動マイグレーションも実装。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| UserDefaults (plist) | 実装容易 | 平文保存、セキュリティ脆弱 | API キーには不適切 |
| .env ファイル | 開発者に馴染み | Git にコミットされるリスク | 事故リスク高 |
| 独自暗号化ファイル | カスタム可能 | 鍵管理が別途必要 | Keychain で十分 |

## Consequences

### Positive
- OS レベルの暗号化で API キーを安全に保存
- Touch ID / パスワードによるアクセス制御が OS 側で提供
- 3段階フォールバック（Keychain → UserDefaults移行 → 環境変数）で開発体験も確保

### Negative
- Keychain API の複雑さ（SecItemAdd/Update/CopyMatching）
- 環境変数フォールバックが本番環境で意図せず有効化されるリスク

### Risks
- アドホック署名では Keychain アクセスに制約が出る可能性

## References

- Sources/Services/APIKeyStore.swift
- Apple: Keychain Services API Reference
