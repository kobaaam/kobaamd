---
title: AI サービス層（削除済み・歴史的記録）
category: components
tags: [ai, openai, anthropic, keychain, streaming, removed]
sources: [docs/adr/0005-ai-multi-provider-rest.md, docs/adr/0006-keychain-api-key-storage.md]
created: 2026-04-30
updated: 2026-07-02
---

# AI サービス層（削除済み・歴史的記録）

> **注意**: 本記事が説明するコンポーネント（AIService / APIKeyStore / AIChatView / AIChatViewModel）は **削除済み** である。
> 削除コミット: `2111871` ("Re-concept: strip secrets/Sparkle, refresh E1 MD layout")
> 削除理由: アプリ再コンセプト化（Re-concept）に伴い、Keychain API キー管理・AI チャット機能・Confluence 連携・Sparkle 自動アップデートをすべて除去。アプリが起動時に資格情報を要求しないシンプルな設計に変更された。
> この記事は設計思想の参考記録として保持するが、コードは現在の main ブランチに存在しない。

## Summary

AIService + APIKeyStore でマルチプロバイダー AI 連携を実現していた。Keychain ベースの安全なキー管理と SSE ストリーミングを提供していたが、Re-concept でアプリコアから除去された。

## AI サービス層の設計（削除済み）
<!-- llm-context: AIService / APIKeyStore / AIChatView / AIChatViewModel の設計。コミット 2111871 で削除。現在の main には存在しない歴史的記録。 -->

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

### セキュリティ考慮事項（当時）

- UI の API キー入力に SecureField 未使用（改善余地として認識していた）
- 環境変数フォールバックの本番での意図しない有効化リスク

## Related

- [[editor-core]] — 削除前は AI インライン補完の呼び出し元だった（現在は AI 補完機能も削除済み）
- [[multi-llm-persona]] — エディタ内 AI とパイプライン AI の使い分け（現在はパイプライン側のみ残存）

## Sources

- docs/adr/0005-ai-multi-provider-rest.md
- docs/adr/0006-keychain-api-key-storage.md
