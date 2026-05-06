# Wiki Index

kobaamd の設計思考・技術知見の知識ベース。

## Architecture（アーキテクチャ）

- [WKWebView 共存戦略とメモリ管理](articles/architecture/wkwebview-strategy.md) — 4つの WKWebView の役割分担、JS バンドル戦略、差分更新パターン、100MB メモリ目標への対策

## Concepts（概念・パターン）

- [MVVM と Observable パターン](articles/concepts/mvvm-observable.md) — SwiftUI での状態管理設計、@Observable の利点と MVVM 境界の守り方
- [AppKit-SwiftUI ブリッジ](articles/concepts/appkit-swiftui-bridge.md) — NSViewRepresentable パターン、NSTextView ラップの設計判断と macOS バージョン差異

## Decisions（意思決定の文脈）

- [AI 自律開発パイプラインの設計思想](articles/decisions/autonomous-pipeline-philosophy.md) — なぜ Linear + subagent 構成を選んだか、人間承認ゲートの設計意図
- [マルチ LLM ペルソナ体制](articles/decisions/multi-llm-persona.md) — Claude/Codex/Gemini の役割分担、Opus/Sonnet のモデル割り当て基準

## Components（コンポーネント知識）

- [エディタコア (NSTextViewWrapper)](articles/components/editor-core.md) — テキスト編集の中核、シンタックスハイライト、行番号、Find/Replace の実装構造
- [AI サービス層](articles/components/ai-service.md) — AIService/APIKeyStore の設計、マルチプロバイダー対応、ストリーミング SSE
- [D2 ダイアグラムプレビュー](articles/components/d2-diagram-preview.md) — D2 CLI による SVG レンダリング、WKWebView + svg-pan-zoom.js のインタラクティブ表示
- [ファイルツリーとアウトラインの同期](articles/components/file-tree-outline-sync.md) — FileTreeViewModel/OutlineViewModel の走査・抽出ロジック、サイドバー分割パネル構成、エディタとの双方向同期

## Practices（開発プラクティス）

- [PRD 品質基準と改善サイクル](articles/practices/prd-quality-cycle.md) — 10セクション PRD の品質バー、レビュー↔修正ループ、学んだ教訓
- [ポストモーテムから学ぶ実装パターン](articles/practices/postmortem-patterns.md) — KMD-4/6/20/22 の振り返りから抽出した再発防止パターン
- [セキュリティ・ハードニング](articles/practices/security-hardening.md) — AI パイプライン固有リスクへの多層防御（pre-commit + review_security + 将来 CI）
- [Sparkle 署名付きリリース手順](articles/practices/sparkle-release.md) — EdDSA 鍵ペア生成、公開鍵の環境変数注入、DMG 署名と appcast 生成までのリリースフロー
- [Wiki 参照ポリシー（Prompt Caching 標準運用）](articles/practices/wiki-reference-policy.md) — wiki 全件 Prompt Caching 投入を Phase 1 標準とし、検索層は 20 万トークン超過まで導入しない。Opus/Sonnet/Haiku の使い分け方針も収録
- [kobaamd チーム構成（コアチーム = subagent / slash 体制）](articles/practices/team-structure.md) — 人間 PM 1 名 + AI ロール群の組織図。各ロールの責務・モデル・呼び出し元・成果物 + 俯瞰役（health_check / report_status）+ halted リカバリ
- [外付けチーム（外部依存サービス・SDK・LLM）](articles/practices/external-teams.md) — Linear / GitHub / launchd / Sparkle / Codex / Gemini / Anthropic API 等の外部依存と halted 経験の集約
- [ロールディスパッチ（タスク → ペルソナ → モデル → フォールバック）](articles/practices/role-dispatch.md) — 入力サインからペルソナ・モデル・halted 時の degrade 経路を 1 枚に集約。Phase A コスト最適化 (KMD-119〜123) と halted リカバリ (PR #59) を統合した 4 層辞書 + SSOT ルール
