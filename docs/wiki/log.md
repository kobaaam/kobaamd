# Wiki Log

操作履歴（追記専用）。

## [2026-04-30] Wiki 初期構築

- SCHEMA.md 作成（Karpathy LLM Wiki パターン準拠）
- index.md 作成（8記事のスケルトン）
- 初期記事 8件を作成（concepts 2, decisions 2, components 2, practices 2）
- ソース: ADR 0001-0008, docs/learnings/KMD-4,6,20,22, CLAUDE.md

## [2026-04-30] Architecture カテゴリ追加

- `articles/architecture/wkwebview-strategy.md` 作成（WKWebView 共存戦略とメモリ管理）
- index.md に Architecture セクション追加
- ソース: MarkdownWebView.swift, D2WebView.swift, WYSIWYGEditorView.swift, BundledJS.swift, MarkdownService.swift, ADR-0004

## [2026-04-30] D2 ダイアグラムプレビュー記事追加

- articles/components/d2-diagram-preview.md を新規作成
- index.md の Components セクションに追加
- ソース: D2Service.swift, D2WebView.swift, D2PreviewViewModel.swift, BundledJS.swift

## [2026-05-04] Wiki 参照ポリシー記事追加（KMD-49）

- `articles/practices/wiki-reference-policy.md` を新規作成（Phase 1 Prompt Caching 標準運用、Phase 移行トリガー、Opus/Sonnet/Haiku 使い分け、Haiku 必須ルール 4 項目）
- `SCHEMA.md` の「ワークフロー > Query」節を Phase 1 標準手順 + フォールバック手順 + Phase 移行トリガーに更新
- `CLAUDE.md`（gitignore 管理）にも同等の内容を「自律開発パイプライン > Wiki 参照ポリシー」と「モデル割り当て方針 > Haiku の用途」として追記
- index.md の Practices セクションに新記事を登録
- ソース: KMD-45, KMD-46（scripts/wiki/load_all.sh）, KMD-47（scripts/wiki/ask.sh）, KMD-48, KMD-49

## [2026-05-06] ロール定義整理 + SSOT ルール明文化 + Phase 監視組込

ハンドオフ文書 `docs/handoff/2026-05-06-cost-optimization-prompt.md` を踏まえ、コスト最適化 (KMD-117〜123) と halted リカバリ (PR #59) を統合したロール定義 3 記事を整備し、SSOT ルールと Phase 監視を仕組み化。

- `articles/practices/team-structure.md` を**再作成**（5/1 作成分が stash 操作で消失していた）
- `articles/practices/external-teams.md` を**再作成**（同上、halted 経験の集約節追加）
- `articles/practices/role-dispatch.md` を**新規作成**（4 層辞書 + SSOT ルール節）
- `scripts/hooks/pre-push` に `docs/wiki/articles/` 未コミット警告を追加（block しないが消失リスクを通知）
- `.claude/commands/kobaamd_health_check.md` に Phase 移行トリガー監視ステップを追加（wiki 総量を `scripts/wiki/load_all.sh` で計測、12万 / 15万 / 18万 / 20万トークン閾値で WARNING / CRITICAL）
- index.md の Practices セクションに 3 件追加
- KMD-119〜123（Phase A コスト最適化 5 件）の priority を 4 → 3 (Normal) に上げ、人間承認済とみなして todo に進められる状態に
- ソース: docs/handoff/2026-05-06-cost-optimization-prompt.md, KMD-117〜123, PR #59 (halted リカバリ), recover_halted.sh, scripts/wiki/load_all.sh, .claude/agents/, .claude/commands/, 既存 wiki 記事群

## [2026-05-06] Wiki ingest（review_postmortem KMD-144）

- sources:
  - docs/learnings/2026-05-06-KMD-144.md
- updated articles:
  - articles/practices/postmortem-patterns.md（パターン 12 / 13 / 14 を新規追加: 観測機構の自己観測責務 / auto-carveable 統合チケット化 / Reviewed 直行 3 条件）
  - articles/practices/security-hardening.md（サイレント失敗パターン表に「予防機構の自己観測欠如」行を追記、シェルクォート規約に `set -u` + `trap` + `local` 互換性ルールを追加）
  - articles/decisions/autonomous-pipeline-philosophy.md（auto carve-out フローの判断条件節を新設: Reviewed 直行 3 条件 + 統合チケット化 3 条件）
- new articles: なし
- skipped sources（理由付き）: なし
- lint: pass (./scripts/wiki/lint.sh --no-llm exit=0, violations=0)
- ingest history: ok (status=pass, consecutive=0/threshold=5)
