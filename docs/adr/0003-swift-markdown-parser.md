# ADR-0003: swift-markdown (Apple) をパーサーに採用

- **Status**: accepted
- **Date**: 2025-12-01
- **Deciders**: 人間
- **Related**: ADR-0004

## Context

Markdown のパース・AST 変換に使うライブラリの選定。正確な CommonMark 準拠と Swift ネイティブの型安全性が要件。

## Decision

Apple 公式の **swift-markdown** (`apple/swift-markdown`) を採用。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| cmark (C) | 高速、広く使用 | Swift 型なし、メモリ管理手動 | Swift ネイティブを優先 |
| Down | Swift ラッパーあり | cmark 依存、メンテ停滞 | apple/swift-markdown の方が公式 |
| Ink (Sundell) | Swift 純製 | CommonMark 非準拠部分あり | 標準準拠を重視 |

## Consequences

### Positive
- Apple 公式で長期メンテナンス期待
- Swift ネイティブ AST（Visitor パターン）で型安全
- GFM 拡張（テーブル、タスクリスト）対応

### Negative
- バージョン 0.x 系のため破壊的変更リスク（Package.resolved で固定対応）
- カスタム構文拡張の仕組みが限定的

## References

- https://github.com/apple/swift-markdown
- Package.resolved: version 0.7.3, revision 7d9a5ce
