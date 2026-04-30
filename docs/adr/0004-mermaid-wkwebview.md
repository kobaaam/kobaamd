# ADR-0004: Mermaid.js + WKWebView によるダイアグラムレンダリング

- **Status**: accepted
- **Date**: 2026-01-15
- **Deciders**: 人間, Gemini（調査）
- **Related**: ADR-0002

## Context

Markdown 内のダイアグラム（フローチャート、シーケンス図等）をプレビューに表示する必要がある。ネイティブ描画ライブラリは macOS 向けに成熟したものがない。

## Decision

**Mermaid.js** を **WKWebView** 内で実行してレンダリングする。D2 も同じ WKWebView パターンで対応。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| PlantUML (Java) | 機能豊富 | JVM 依存、起動遅い | 配布サイズ・UX |
| ネイティブ Core Graphics | 最高速 | 実装コスト膨大 | 費用対効果 |
| SwiftUI Canvas | ネイティブ | ダイアグラム文法パーサーが必要 | 車輪の再発明 |

## Consequences

### Positive
- Mermaid.js の豊富なダイアグラム種別をそのまま利用
- Web エコシステムの更新に追従しやすい
- プレビュー全体を WKWebView に統一でき一貫性が高い

### Negative
- WKWebView のメモリ消費（100MB 目標に影響: feedback_performance.md 参照）
- JavaScript 実行のオーバーヘッド
- WKWebView の sandbox 制約

### Risks
- WKWebView の挙動が macOS バージョンで変わるリスク

## References

- https://mermaid.js.org/
- feedback_performance.md（WKWebView メモリ制約）
