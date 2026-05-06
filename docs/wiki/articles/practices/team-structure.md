---
title: kobaamd チーム構成（コアチーム = subagent / slash 体制）
category: practices
tags: [team, persona, subagent, organization, roles]
sources: [.claude/agents/, .claude/commands/, CLAUDE.md, docs/wiki/articles/decisions/multi-llm-persona.md, scripts/recovery/recover_halted.sh, KMD-117]
created: 2026-05-01
updated: 2026-05-06
---

# kobaamd チーム構成（コアチーム = subagent / slash 体制）

## Summary

kobaamd の開発体制を「組織図」として一覧化する。コアチームは人間 1 名（PM 兼アーキテクト）と AI ロール群（メインセッション + 各 subagent / slash）で構成。各ロールの責務・モデル・呼び出し元・成果物を一望できる参照点として機能する。LLM 割当ポリシー（Opus / Sonnet / Haiku の判断基準）の正本は [[wiki-reference-policy]]。「いつ誰が動くか」のディスパッチは [[role-dispatch]]。

## Content

### コアチーム（人間 1 + AI ロール群）

| ロール | 担当 | モデル | 主な責務 | 呼び出し元 |
|---|---|---|---|---|
| **人間 PM / Architect** | h.kobayashi02 | — | 要件発見、PRD 承認、Reviewed 遷移、`Human in Review` での仕様判断、緊急 hotfix の最終承認 | — |
| **Orchestrator** | メインセッション (Claude) | **Opus** | 設計判断、subagent オーケストレーション、緊急 hotfix の手動 PR、Codex / Gemini への依頼設計 | 人間が直接対話 |
| **リサーチャー** | `kobaamd_research_create_ticket` | **Opus** | 新機能候補の発掘、PRD-lite で backlog 起票（`ai-research` ラベル） | `pipeline_weekly` |
| **PRD ライター** | `kobaamd_create_prd` | **Opus** | draft → backlog 昇格、10 セクション PRD 作成、AC 定義 | `pipeline_active` フェーズ B / 手動 |
| **PRD レビュアー** | `kobaamd_review_prd` | **Opus** | PRD 品質バー検査（別人格）、AC 不足 / 影響範囲漏れ指摘 | `pipeline_active` フェーズ B / 手動 |
| **WIP 制御** | `kobaamd_assign_work` | (slash) | todo から 1 件選定、WIP=1 制御 | `pipeline_active` フェーズ B |
| **実装担当** | `kobaamd_implement_code` → Codex CLI | **Opus** + Codex (gpt-5.5) | Swift 実装、ブランチ作成、コミット、PR 作成。**WIP commit 義務化** | `assign_work` 経由 / 手動 |
| **ビルド検証** | `kobaamd_validate_build` | **Sonnet** | `swift build` + `swift test` 実行、結果を Linear に記録 | `pipeline_active` ステップ 9 / 手動 |
| **PR レビュアー（機能）** | `kobaamd_review_pr` | **Opus** | コード批判レビュー、PRD AC 整合、影響範囲整合、UI/UX (Gemini 連携)、サイレント失敗検出。concern を rework / auto-carveable / human-judgment に 3 分類 | `pipeline_active` ステップ 10a / 手動 |
| **PR レビュアー（セキュリティ）** | `kobaamd_review_security` | **Opus** | サプライチェーン、シークレット、コード安全性、権限変更、ビルド改竄を検査 | `pipeline_active` ステップ 10a（review_pr と並行） |
| **PR コメント修正** | `kobaamd_fix_pr_comments` | **Sonnet** | REQUEST_CHANGES の指摘を Codex に修正依頼 → push → in-review 復帰。**WIP commit 義務化** | `pipeline_active` レビュー↔修正ループ / 手動 |
| **リワーク担当** | `kobaamd_rework_issue` | **Opus** | `Human in Review` の人間コメントを 5 カテゴリ分類 → PRD 更新 → 再実装 → PR 更新。**WIP commit 義務化** | `pipeline_active` ステップ 4 / 手動 |
| **carve-out 担当** | `kobaamd_carve_concerns` | (slash) | concern を別 issue に退避（draft / backlog 直入れ） | `rework_issue` の carve カテゴリ / 手動 |
| **マージ担当** | `kobaamd_merge_pr` | **Sonnet** | `Reviewed` の issue を main に squash merge → done。`Human in Review` でマージ済みのクリーンアップも担当 | `pipeline_active` フェーズ A ステップ 5 / 手動 |
| **postmortem ライター** | `kobaamd_review_postmortem` | **Opus** | done の振り返りを `docs/learnings/<date>-<KMD-XX>.md` に出力 | `pipeline_active` ステップ 11 / 手動 |
| **wiki 担当** | `kobaamd_update_wiki` | **Opus** | learnings / ADR を articles に蒸留、矛盾検出、ingest 履歴を log.md に追記 | `review_postmortem` 完了時 / `pipeline_weekly` / 手動 |
| **wiki lint 担当** | `kobaamd_lint_wiki` | **Sonnet** | `docs/wiki/articles` を 5 観点（孤立 / リンク切れ / stale / セクション単独文脈 / frontmatter 整合）で lint | 手動 / `pipeline_weekly` |
| **改善案ジェネレータ** | `kobaamd_improve_prompt` | **Opus** | learnings から各 subagent のプロンプト改善案を提案 | `pipeline_weekly` / 手動 |
| **リサーチャー / DocWriter** | Gemini API | gemini-3.1-pro-preview | 調査・ドキュメント生成・UI/UX 検証 | `review_pr` の UI/UX サブステップ / 手動 |

### 補助スラッシュ（運用ユーティリティ）

| ロール | 用途 |
|---|---|
| `kobaamd_snapshot_state` | Linear 全 issue 状態を `.logs/pipeline_state.json` にスナップショット |
| `kobaamd_archive_done` | done 滞留 issue をアーカイブ（Linear free 250 件制限対策） |
| `kobaamd_detect_stale` | N 日以上動いていない issue を検出 |
| `kobaamd_sync_github` | GitHub Issues → Linear draft 片方向同期 |
| `kobaamd_format_code` | swift-format / lint を一括実行 |
| `kobaamd_summarize_changelog` | done 集約 → リリースノート Markdown |
| `kobaamd_run_pipeline` | 全パイプライン手動 1 周（プレゼン用） |
| `scripts/recovery/recover_halted.sh` | halted PR の自動復帰（commit + push + PR + `[halted-recovered]` ラベル）。`pipeline_active` step 0c で `--auto` 起動 |

### 俯瞰役（EM + PM）

縦割りの個別 subagent では検出できない、横串の停滞・異常を検知する役割。

| ロール | 担当 | モデル | 主な責務 | 起動タイミング |
|---|---|---|---|---|
| **基盤監視（EM 寄り）** | `kobaamd_health_check` | **Sonnet** | launchd 死活、pipeline_active 稼働間隔、Linear API 疎通、環境変数、API キー、ログサイズ、ディスク空き、**wiki 総量（Phase 移行トリガー）** をチェック。CRITICAL 検出時は Linear に `[infra/health]` issue を起票 | `pipeline_daily` ステップ 0（毎日 8:00）/ 手動 |
| **ステアリングレポート（PM + EM 俯瞰）** | `kobaamd_report_status` | **Opus** | リードタイム / レビュー回数 / carve-out 件数 / 健康診断履歴を集計し、異常値検出と次着手提案 | `pipeline_weekly` / 手動 |

### パイプラインバンドル

| バンドル | 頻度 | 中身 |
|---|---|---|
| `kobaamd_pipeline_active` | 30 分 | フェーズ A（既存 PR 処理 + halted 復帰）+ フェーズ B（新チケット完全サイクル × 最大 5）|
| `kobaamd_pipeline_daily` | 毎日 8:00 | `health_check` → `archive_done` → `detect_stale` → `sync_github` |
| `kobaamd_pipeline_weekly` | 毎週月 9:00 | `research_create_ticket` → `report_status` → `summarize_changelog` → `improve_prompt` → `update_wiki` |

詳細は [[autonomous-pipeline-philosophy]]。

### モデル割当原則（要約、正本は [[wiki-reference-policy]]）

| 分類 | モデル |
|---|---|
| Orchestrator | **Opus** |
| 判断・創造・分析系 subagent | **Opus** |
| 機械的操作系 subagent | **Sonnet** |
| 大量バッチ系（Haiku 必須 4 ルール準拠） | **Haiku** |

### 外部 LLM の役割

| LLM | 役割 |
|---|---|
| **Claude Opus / Sonnet / Haiku** | Orchestrator + 判断系 + 機械系 + wiki query |
| **Codex CLI (gpt-5.5)** | Swift 実装 / リファクタ |
| **Gemini (gemini-3.1-pro-preview)** | 調査 / DocWriter / UI/UX 検証 |

外部依存全体は [[external-teams]] を参照。

### halted リカバリ（PR #59 で確立）

1. **WIP commit 義務化**: implement_code / rework_issue / fix_pr_comments が swift build パス直後に commit + push（`--no-verify` 禁止）
2. **`scripts/recovery/recover_halted.sh`**: halted 状態を自動検出 → commit → push → PR 作成 → `[halted-recovered]` ラベル付与
3. **pipeline_active step 0c**: 上記スクリプトの `--auto` 起動を毎回実行

詳細な degrade 経路は [[role-dispatch]] §6 を参照。

## Related

- [[role-dispatch]] — タスク → ペルソナ → モデル → フォールバックの 4 層辞書
- [[multi-llm-persona]] — Opus / Sonnet / Codex / Gemini の役割分担ポリシー
- [[autonomous-pipeline-philosophy]] — パイプライン全体の設計思想
- [[external-teams]] — 外付けチーム（外部依存サービス・SDK）の一覧
- [[concern-carve-out]] — review_pr の concern 3 分類とロール連携
- [[wiki-reference-policy]] — Phase 1 wiki 参照ポリシーと Haiku 必須ルール

## Sources

- `.claude/agents/*.md` — subagent 定義
- `.claude/commands/*.md` — slash command 定義
- `CLAUDE.md` — 自律開発パイプライン / モデル割当方針
- `docs/wiki/articles/decisions/multi-llm-persona.md`
- `scripts/recovery/recover_halted.sh`（PR #59 で実装）
- KMD-117（コスト最適化 + halted リカバリ epic）
