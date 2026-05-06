---
title: 外付けチーム（外部依存サービス・SDK・LLM）
category: practices
tags: [external, dependencies, integration, services, organization, halted]
sources: [CLAUDE.md, scripts/linear/lq.sh, scripts/launchd/, docs/wiki/articles/practices/sparkle-release.md, scripts/recovery/recover_halted.sh, KMD-117]
created: 2026-05-01
updated: 2026-05-06
---

# 外付けチーム（外部依存サービス・SDK・LLM）

## Summary

kobaamd のコアチーム外で連携する外部サービス・SDK・LLM の一覧。各依存の関わるタイミング、責務、認証方式、halted 履歴を整理する。コアチーム構成は [[team-structure]]、halted 時の degrade 経路は [[role-dispatch]] §6 を参照。

## Content

### Linear（タスク管理）

| 項目 | 内容 |
|---|---|
| 関わるタイミング | 全フェーズ |
| 主な責務 | issue 状態管理、PRD 格納、コメント、優先度判定、ラベル管理 |
| ワークスペース / チーム | kobaan workspace / KMD team |
| 接続アカウント | `es57ster+claude@gmail.com`（AI コメント分離用） |
| 認証 | `$LINEAR_API_KEY`（`~/.zshrc`） |
| アクセス経路 | `scripts/linear/lq.sh` 経由のみ（hosted MCP は撤去済み） |
| 監査ログ | `.logs/linear_writes.jsonl`、ID キャッシュ `.logs/linear_cache.json` |
| halted 時 | API エラー時はリトライ 3 回 → スキップ。pipeline_active 全体は止めない |

### GitHub（コード管理 / PR / Releases）

| 項目 | 内容 |
|---|---|
| リポジトリ | `kobaaam/kobaamd`（OSS, Public） |
| 認証 | `gh` CLI |
| halted ラベル運用 | `[halted-recovered]` / `[halted-codex]` / `[review-pending-halted]` をパイプラインが付与 |

### launchd（個人 Mac の定期実行基盤）

| 項目 | 内容 |
|---|---|
| 主な責務 | `pipeline_active`(30 分) / `pipeline_daily`(8:00) / `pipeline_weekly`(月 9:00) のトリガー |
| 配置 | `~/Library/LaunchAgents/com.kobaamd.*.plist` |
| インストーラ | `./scripts/launchd/install.sh`（`__KOBAAMD_DIR__` プレースホルダを sed で実パス置換） |
| halted 経験 | 2026-05-01 に `EX_CONFIG (78)` で 33 回連続失敗。`__KOBAAMD_DIR__` 未置換 plist が原因。`health_check` で検出可能 |

### Sparkle（自動アップデート）

| 項目 | 内容 |
|---|---|
| 関わるタイミング | リリース時のみ |
| 鍵管理 | 秘密鍵: macOS Keychain。公開鍵: env `KOBAAMD_SU_PUBLIC_ED_KEY` → post-build で `Info.plist` に注入 |
| 配布物バンドル | `scripts/post-build.sh` が `.app/Contents/Frameworks/Sparkle.framework` にコピー（KMD-35） |
| 詳細 | [[sparkle-release]] / [[security-hardening]] |

### macOS Codesign / Notarization

| 項目 | 内容 |
|---|---|
| 経路 | `codesign --force --deep --sign - --options runtime "$APP"` |
| 検証 | `codesign --verify --verbose`、`codesign --display --verbose=4` |

### OpenAI ChatGPT Plus（Codex CLI / 実装担当）

| 項目 | 内容 |
|---|---|
| モデル | gpt-5.5（ChatGPT Plus 認証時のデフォルト） |
| 認証 | `~/.codex/auth.json` の `auth_mode: chatgpt`（`codex login` で再認証） |
| 呼び出し | `codex exec` |
| halted 経験 | KMD-9 / KMD-17 でクォータ超過によりパイプライン停止。KMD-123 で 3 subagent 共通の 429 ハンドラを切り出す予定 |

### Google Gemini API（Researcher / DocWriter / UI/UX 検証）

| 項目 | 内容 |
|---|---|
| モデル | gemini-3.1-pro-preview |
| 認証 | `$GEMINI_API_KEY`（`~/.zshrc`） |
| 呼び出し | `curl https://generativelanguage.googleapis.com/v1beta/models/...` |
| halted 経験 | KMD-25 で review_pr が Gemini を 6 回呼んで爆発。KMD-122 で Linear コメント履歴ベースの機械ゲートで重複呼び出し抑制予定 |

### Anthropic API（メイン LLM）

| 項目 | 内容 |
|---|---|
| モデル | Opus 4.7 / Sonnet 4.6 / Haiku 4.5（用途別） |
| 認証 | Claude Code（CLI） + `$ANTHROPIC_API_KEY`（`scripts/wiki/ask.sh` 用） |
| halted 経験 | 2026-05-05 に `org's monthly usage limit` 到達。PR #59 で WIP commit 義務化 + `recover_halted.sh` を導入し、次サイクルでの自然復帰経路を確立 |
| 関連ポリシー | [[wiki-reference-policy]]（Phase 1 Prompt Caching + Haiku 必須ルール）、[[role-dispatch]] |

### macOS Keychain

| 項目 | 内容 |
|---|---|
| 主な責務 | Sparkle 秘密鍵の安全な保管 |
| アクセス | `generate_keys` / `sign_update` バイナリ経由 |

### npm / Node.js（補助ツール）

| 項目 | 内容 |
|---|---|
| 主な責務 | mermaid バンドル、d2 wasm、svg-pan-zoom 等の JS 資産の事前ビルド |
| 配置 | `Sources/Resources/kobaamd_kobaamd.bundle` 配下（runtime には node 不要） |

### 将来追加予定の外部依存（候補）

| サービス | 用途 | ステータス |
|---|---|---|
| **GitHub Actions** | CI/CD（自動テスト、dependency audit、SBOM 生成） | 検討中 |
| **Notarization (Apple)** | macOS 配布物の公証 | 検討中 |
| **Sentry 等** | クラッシュレポート / テレメトリ | 未導入 |
| **Slack / Discord** | パイプラインの完了通知 | 一部導入済み（`KOBAAMD_SLACK_WEBHOOK_URL` env） |

## 認証情報の管理ポリシー

- **`~/.zshrc`** に集約: `LINEAR_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` / `ANTHROPIC_API_KEY` / `KOBAAMD_SU_PUBLIC_ED_KEY` 等
- **`source ~/.zshrc`** を pipeline_active / 各 subagent の事前確認ステップで実行（KMD-131 で冗長読み込み解消予定）
- **コミットしてはいけないファイル**: `.env` / `*.pem` / `*.key` / `credentials.json` / `.mcp.json`（pre-commit hook + `.gitignore` で多層防御）

## halted 経験の集約

| 日付 | 対象 | 原因 | 解消経路 |
|---|---|---|---|
| 2026-04-30 | OpenAI Codex（KMD-9） | クォータ超過 | 月次補充待ち、または手動着手 |
| 2026-04-30 | OpenAI Codex（KMD-17） | クォータ超過 | 同上 |
| 2026-05-01 | launchd `pipeline_active` | `__KOBAAMD_DIR__` 未置換 plist で `EX_CONFIG (78)` 33 回連続失敗 | `install.sh` 再実行で再 bootstrap。以後 `health_check` で検出可能 |
| 2026-05-05 | Anthropic | 月次 usage limit | PR #59 の WIP commit + `recover_halted.sh` で次サイクル自然復帰 |

これらの経験から、KMD-117 epic 配下で halted リカバリ機構（PR-B 系列）と事前 usage チェック（KMD-128）を整備中。

## Related

- [[team-structure]] — コアチーム（subagent / slash 体制）の組織図
- [[role-dispatch]] — 各外部依存に対する halted 時の degrade 経路
- [[autonomous-pipeline-philosophy]] — パイプラインの設計思想
- [[sparkle-release]] — Sparkle 連携の詳細手順
- [[security-hardening]] — シークレット管理と外部依存に対する多層防御
- [[wiki-reference-policy]] — Anthropic API の Phase 1 運用

## Sources

- `CLAUDE.md` — 自律開発パイプライン、APIキー、Linear I/O ポリシー
- `scripts/linear/lq.sh` — Linear I/O 単一エントリポイント
- `scripts/launchd/` — plist と install.sh
- `scripts/recovery/recover_halted.sh`（PR #59 で実装）
- `docs/wiki/articles/practices/sparkle-release.md`
- KMD-117（コスト最適化 + halted リカバリ epic）
- `docs/handoff/2026-05-06-cost-optimization-prompt.md`
