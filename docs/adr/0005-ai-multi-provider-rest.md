# ADR-0005: AI 連携はマルチプロバイダー REST API 方式

- **Status**: accepted
- **Date**: 2026-02-01
- **Deciders**: 人間
- **Related**: ADR-0006

## Context

エディタ内の AI 機能（補完、チャット、アシスト）で使用する LLM バックエンドの接続方式を決定する必要がある。

## Decision

**REST API を直接呼び出すマルチプロバイダー方式**を採用。OpenAI と Anthropic をプロバイダーとしてサポートし、ユーザーが API キーを設定して切り替える。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| ローカル LLM (llama.cpp) | プライバシー、オフライン | GPU 要件、品質劣る | ユーザー環境依存が大きい |
| 単一プロバイダー固定 | 実装シンプル | ベンダーロックイン | 柔軟性を重視 |
| SDK 依存 (openai-swift等) | 型安全 | 依存増、更新追従コスト | 薄いラッパーで十分 |

## Consequences

### Positive
- ユーザーが好みの LLM を選択可能
- 依存ライブラリを増やさない（URLSession のみ）
- プロバイダー追加が容易（APIService にケース追加のみ）

### Negative
- 各プロバイダーの API 差異を自前で吸収する必要
- ストリーミング SSE パースの実装コスト

### Risks
- API キー管理のセキュリティ（Keychain で対応済み: ADR-0006 参照）

## References

- Sources/Services/AIService.swift
- Sources/Services/APIKeyStore.swift
