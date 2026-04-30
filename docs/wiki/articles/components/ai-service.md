---
title: AI サービス層
category: components
tags: [ai, openai, anthropic, keychain, streaming]
sources: [docs/adr/0005-ai-multi-provider-rest.md, docs/adr/0006-keychain-api-key-storage.md]
created: 2026-04-30
updated: 2026-04-30
---

# AI サービス層

## Summary

AIService + APIKeyStore でマルチプロバイダー AI 連携を実現。Keychain ベースの安全なキー管理と SSE ストリーミングを提供。

## Content

### AIService の設計

`AIServiceProtocol` を定義し、テスト時にモック注入可能。3つの API メソッド:

1. `complete()` — 一括応答（非ストリーミング）
2. `stream()` — SSE ストリーミング（プロンプト + コンテキスト）
3. `streamChat()` — マルチターンチャット用ストリーミング

### プロバイダー切り替え

`APIKeyStore.Provider` enum で OpenAI / Anthropic を管理。各プロバイダーの API 差異（エンドポイント、ヘッダー形式、レスポンス構造）は AIService 内で吸収。

### キー管理の 3段階フォールバック

1. **Keychain** (本番) — OS レベルの暗号化
2. **UserDefaults** (レガシー移行) — 検出時に自動で Keychain に移行
3. **環境変数** (開発用) — `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`

### セキュリティ考慮事項

- UI の API キー入力に SecureField 未使用（改善余地）
- 環境変数フォールバックの本番での意図しない有効化リスク

## Related

- [[editor-core]] — AI インライン補完の呼び出し元
- [[multi-llm-persona]] — エディタ内 AI とパイプライン AI の使い分け

## Sources

- docs/adr/0005-ai-multi-provider-rest.md
- docs/adr/0006-keychain-api-key-storage.md
