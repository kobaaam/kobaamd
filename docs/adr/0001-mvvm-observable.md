# ADR-0001: MVVM + @Observable アーキテクチャ

- **Status**: accepted
- **Date**: 2025-12-01
- **Deciders**: 人間
- **Related**: ADR-0002

## Context

kobaamd は macOS 14+ 向けの Markdown エディタ。SwiftUI を UI フレームワークとして採用する前提で、状態管理パターンを決定する必要があった。

## Decision

**MVVM（Model-View-ViewModel）** を採用し、ViewModel には Swift 5.9 の `@Observable` マクロを使用する。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| MVC | シンプル | View が肥大化しやすい | SwiftUI との相性が悪い |
| TCA (Composable Architecture) | テスタビリティ高い | 学習コスト大、ボイラープレート多い | 個人開発の速度を重視 |
| ObservableObject + @Published | 実績あり | パフォーマンス劣る（全プロパティ監視） | @Observable の方が効率的 |

## Consequences

### Positive
- View と ビジネスロジックの分離が明確
- `@Observable` によりプロパティ単位の更新で高パフォーマンス
- SwiftUI の標準パターンに沿っており学習コストが低い

### Negative
- View が ViewModel を直接参照する慣習が生まれやすい（Service 直呼び問題: KMD-20 postmortem 参照）
- macOS 14+ 必須（`@Observable` の最低要件）

### Risks
- ViewModel が肥大化した場合の分割指針が未定義

## References

- Apple WWDC23: Discover Observation in SwiftUI
- docs/learnings/2026-04-29-KMD-20.md（MVVM 境界違反の教訓）
