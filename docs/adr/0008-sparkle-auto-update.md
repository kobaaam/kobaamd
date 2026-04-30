# ADR-0008: Sparkle によるアプリ自動アップデート

- **Status**: accepted
- **Date**: 2026-03-01
- **Deciders**: 人間
- **Related**: ADR-0005

## Context

OSS として配布する macOS アプリに、ユーザーが手動でダウンロードし直さなくても更新できる仕組みが必要。Mac App Store 外での配布を前提とする。

## Decision

**Sparkle** フレームワーク (`sparkle-project/Sparkle`) を採用。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| Mac App Store | 自動更新標準装備 | 審査プロセス、sandbox 制約 | OSS の自由度を優先 |
| 手動ダウンロード | 依存ゼロ | UX 悪い | ユーザー離脱リスク |
| 自前実装 | カスタム可 | セキュリティ実装コスト大 | Sparkle が業界標準 |

## Consequences

### Positive
- macOS アプリの自動アップデートの業界標準
- EdDSA 署名によるアップデートの改竄検知
- appcast.xml ベースでシンプルな配信

### Negative
- XCFramework のバンドルが必要（post-build.sh で対応）
- rpath 設定が SwiftPM ビルドでは自動化されない

### Risks
- Sparkle 自体のサプライチェーンリスク（信頼できるプロジェクトだが監視は必要）

## References

- https://sparkle-project.org/
- Package.resolved: version 2.9.1, revision 066e75a
- scripts/post-build.sh（Sparkle.framework コピー処理）
