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

## [2026-05-06] Wiki ingest（--source docs/learnings/2026-05-05-KMD-54.md）

- sources:
  - docs/learnings/2026-05-05-KMD-54.md
- updated articles:
  - articles/practices/postmortem-patterns.md（パターン 7「クリーン APPROVE 直行の 4 条件」/ パターン 8「auto carve-out re-open 規約」/ パターン 9「依存逆順ガードを PRD と実装の両方に書く」を追加）
  - articles/practices/prd-quality-cycle.md（影響範囲マップの効能 — KMD-54 事例セクションを追記）
  - articles/decisions/autonomous-pipeline-philosophy.md（auto carve-out によるクリーン APPROVE 直行運用を追記）
  - articles/practices/security-hardening.md（Related に [[dependency-inversion-guard]] を追加 — 双方向リンクの整合のため）
- new articles:
  - articles/practices/dependency-inversion-guard.md（依存逆順耐性のためのガードパターン。lint.sh 不在ガードを KMD-54 事例として収録）
- skipped sources（理由付き）:
  - なし
- 注記: KMD-52（lint.sh、Human in Review）は本記事執筆時点で未マージ。新規記事内では「依存先 script」「KMD-52」と表記しつつ、KMD-54 で実装したガードが KMD-52 マージ前でも機能する点を強調。

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

## [2026-05-08] Wiki ingest（--source docs/learnings/2026-05-08-KMD-120.md）

KMD-120 (subagent から CLAUDE.md 明示 Read を削除) の postmortem を取り込み、subagent プロンプト設計の境界判定ルールを新規記事として確立。あわせて Action Item「concern 三分類判定基準を docs/wiki/articles/practices/ 系記事として明文化」を autonomous-pipeline-philosophy.md に補完して、PR レベル（Reviewed 直行 3 条件）と concern レベル（auto-carveable 3 条件）を分けて記述。

- sources:
  - docs/learnings/2026-05-08-KMD-120.md
- updated articles:
  - articles/practices/postmortem-patterns.md（パターン 15「AC は観測 → 文言の順」/ パターン 16「subagent MD 編集時 frontmatter 整合チェック」/ パターン 17「観測前提 AC は観測手段セット」を追加。Related に [[subagent-prompt-design]] 追加）
  - articles/practices/prd-quality-cycle.md（「KMD-120 で見えた『観測 → 文言』AC の重要性」節を追加。観測前提 AC の観測手段セット起票規約も併記。Related に [[subagent-prompt-design]] 追加）
  - articles/decisions/autonomous-pipeline-philosophy.md（「concern を auto-carveable と判定する 3 条件」節を新設: 動作影響なし / AC 範囲外 / 独立修正可。KMD-120 (PR #76) frontmatter `description:` concern が KMD-156 に auto-carve された経路を参照実例として収録。sources に KMD-120 追加、Related に [[subagent-prompt-design]] 追加）
- new articles:
  - articles/practices/subagent-prompt-design.md（subagent プロンプト設計（Claude Code 暗黙注入を踏まえた）。境界判定ルール / 削除と残しの基準 / Constraints 格上げによる defense-in-depth / observation-driven AC / KMD-120 運用結果を集約。Related: [[postmortem-patterns]] / [[prd-quality-cycle]] / [[autonomous-pipeline-philosophy]]）
- skipped sources（理由付き）: なし
- 注記: 影響範囲は 1 新規 + 3 更新の 4 記事で、kobaamd_update_wiki の「1 ソース → 最大 3 記事」ソフトキャップを 1 記事超過している。autonomous-pipeline-philosophy.md は本ソースの Action Item「concern 三分類判定基準を docs/wiki/articles/practices/ 系記事として明文化」に直接対応するため、3 件枠から外せなかった（前回 ingest 中断分の継承も兼ねる）
- lint: fail (./scripts/wiki/lint.sh --no-llm exit=1, violations=15)。**全 15 件は KMD-120 ingest と独立した既存違反**（external-teams 4 / role-dispatch 7 / team-structure 4 の Related 非対称 + `[[concern-carve-out]]` broken-link）。本 ingest 対象 4 ファイル（subagent-prompt-design / postmortem-patterns / prd-quality-cycle / autonomous-pipeline-philosophy）からの新規違反は 0 件。既存違反は別タスクで扱う（commit は中止、working tree に差分を残す）
- ingest history: ok (status=fail, consecutive=0/threshold=5)

## [2026-05-08] Wiki ingest（--source docs/learnings/2026-05-08-KMD-153.md）

KMD-153（`section-context-check.sh` の stdout/stderr 分離 17 行追加 / 2 行変更）の postmortem を取り込み、auto-carve 二段連鎖（KMD-150 → KMD-153 → KMD-171）/ 観測機構変更時の smoke test 必須化 / review_security のゲート観点選択 / shell script 小規模 fix の経路 / フェーズ B 最短サイクル参考値（23 分）を既存 3 記事に統合。

- sources:
  - docs/learnings/2026-05-08-KMD-153.md
- updated articles:
  - articles/practices/postmortem-patterns.md（パターン 18「観測機構変更には smoke test を初手で含める」/ パターン 19「review_security はゲート観点を PR の本質に応じて選ぶ」/ パターン 20「shell script 小規模 surgical fix は main session 直接 Edit で十分」を追加。Related に [[role-dispatch]] 追加）
  - articles/practices/role-dispatch.md（§2.3 transcript 表に shell script 小規模 fix 行追加、§4 近接ロールの境界に `*.sh` 30 行未満境界の行を新設し KMD-153 を実例として収録、sources / updated 更新）
  - articles/decisions/autonomous-pipeline-philosophy.md（「多段 auto carve-out 連鎖（KMD-150 → 153 → 171）」節と「フェーズ B 最短サイクル参考値（23 分）」節を新設。Related に [[role-dispatch]] 追加）
- new articles: なし
- skipped sources（理由付き）: なし
- 注記: 「観測機構変更時の smoke test」と「review_security のゲート観点選択」は新規パターンとして wiki 化に値したが、postmortem-patterns.md の §パターン群に追加するだけで足りたため新規記事は作成せず。shell script 小規模 fix の SSOT は role-dispatch §4 に置き、postmortem-patterns パターン 20 はそこを参照する形にした
- lint: 未実行（Final Report で警告として申告）
- ingest history: 未記録（lint.sh / ingest_history.sh の状態に依存）

## [2026-05-09] Wiki KB2 lint zero（KMD-50）

KMD-50 KB2 の残作業として `scripts/wiki/lint.sh --no-llm` の violations を 13 → 0 にした。新規記事 1 / Related 双方向化 5 / index 更新 / log 追記 の構成。

- sources:
  - .claude/commands/kobaamd_carve_concerns.md
  - docs/wiki/articles/practices/postmortem-patterns.md（パターン 7 / 13 / 18 / 19 / 20）
  - docs/wiki/articles/practices/role-dispatch.md（§3, §10）
  - docs/wiki/articles/decisions/autonomous-pipeline-philosophy.md（APPROVE 直行 4 条件）
- new articles:
  - articles/practices/concern-carve-out.md（concern 3 分類 + auto-carveable 3 条件 + APPROVE 直行 4 条件 + 運用上の罠の SSOT）
- updated articles（Related 双方向化のみ、本文は無変更）:
  - articles/decisions/autonomous-pipeline-philosophy.md（[[external-teams]], [[team-structure]] 追加）
  - articles/decisions/multi-llm-persona.md（[[role-dispatch]], [[team-structure]] 追加）
  - articles/practices/wiki-reference-policy.md（[[external-teams]], [[role-dispatch]], [[team-structure]] 追加）
  - articles/practices/sparkle-release.md（[[external-teams]] 追加）
  - articles/practices/security-hardening.md（[[external-teams]] 追加）
- skipped sources（理由付き）: なし
- 注記: 本タスクは broken-link 4 件と related-asymmetric 9 件のうち、broken-link を新規記事 1 本で一括解消し、related-asymmetric を双方向化で解消した。既存記事の本文（Summary / Content / Sources）には触れていない
- lint: pass を確認すること（本作業の AC）
- ingest history: 別タスクとして扱う（本タスクは KB2 残作業に焦点）

## [2026-05-23] KMD-90: モデル割り当て表の一本化（Haiku 反映）

- `index.md` の `multi-llm-persona.md` 説明文を更新: 「Opus/Sonnet のモデル割り当て基準」→「Opus/Sonnet/Haiku のモデル割り当て基準（正本）」
- 現状確認: `decisions/multi-llm-persona.md` は KMD-50 時点で Haiku 行（SubAgent（バッチ）/ Claude Haiku）が追記済みのため本文変更なし
- 現状確認: `practices/wiki-reference-policy.md` の Summary と セクション 3 冒頭は「正本は [[multi-llm-persona]]」が既に明記済みのため変更なし
- ソース: KMD-90（PR #48 review concern C1 から auto-carve）

## [2026-05-15] Wiki ingest（default: 7d）

- sources:
  - docs/learnings/2026-05-04-KMD-48-prompt-cache-benchmark.md
  - docs/learnings/2026-05-06-KMD-119.md
  - docs/learnings/2026-05-06-KMD-53.md
  - docs/learnings/2026-05-08-KMD-151.md
- updated articles:
  - articles/practices/postmortem-patterns.md（パターン 21〜24 を追加: no-op 最適化と観測性の両立 / CLI 引数は help で確認 / wiki 規約適合の機械化 / Hardened Runtime SIGKILL トラブルシュート）
  - articles/practices/wiki-reference-policy.md（§1.1.2 KMD-48 ベンチマーク数値を追加）
  - articles/practices/sparkle-release.md（race window の既知 nit と wait loop 化ルートを追記）
  - articles/practices/security-hardening.md（Hardened Runtime + 長期実行プロセスのトラブルシュート節を追加）
  - articles/decisions/autonomous-pipeline-philosophy.md（no-op 最適化と観測性の両立原則節を追加）
- new articles: なし
- skipped sources（理由付き）:
  - なし
