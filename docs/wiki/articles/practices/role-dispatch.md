---
title: ロールディスパッチ（タスク → ペルソナ → モデル → フォールバック）
category: practices
tags: [dispatch, persona, model-selection, halted-recovery, cost-optimization, prompt-caching, ssot]
sources: [docs/wiki/articles/practices/team-structure.md, docs/wiki/articles/practices/wiki-reference-policy.md, docs/wiki/articles/practices/external-teams.md, docs/wiki/articles/decisions/multi-llm-persona.md, .claude/commands/kobaamd_pipeline_active.md, scripts/recovery/recover_halted.sh, docs/learnings/2026-05-08-KMD-153.md, KMD-117, KMD-118, KMD-119, KMD-120, KMD-121, KMD-122, KMD-123, KMD-128]
created: 2026-05-06
updated: 2026-05-08
---

# ロールディスパッチ（タスク → ペルソナ → モデル → フォールバック）

## Summary

入力タスクの種別に応じて **どのペルソナ（subagent / slash / メインセッション）が処理し、どのモデルを使い、halted（usage limit / API エラー / クォータ枯渇）時にどう degrade するか** を 1 枚に集約した辞書。メインセッションも subagent も判断時にこの記事を参照する単一の正本とし、節約・品質・halted 耐性の 3 軸を両立させる。

モデル割当ポリシーは [[wiki-reference-policy]] が正本。本記事は「ペルソナ × halted フォールバック」の追加軸を提供する補完ドキュメント。SSOT（Single Source of Truth）ルールは §10 を参照。

## Content

### 1. ディスパッチの 4 層構造

```
入力サイン → ペルソナ → プライマリ モデル → フォールバック
   (何が発生したか) (誰がやるか) (どれで動かすか) (失敗時の degrade)
```

判断は上から順に降りていく:

1. **入力サイン**: Linear のイベント / パイプラインの定期起動 / transcript の人間入力 / subagent の完了通知 のいずれか
2. **ペルソナ**: [[team-structure]] のロールから 1 つ選ぶ。曖昧なときは「近接ロールの境界」（§4）で判定
3. **プライマリ モデル**: [[multi-llm-persona]] の使い分け基準（**Sonnet 標準** / Opus 例外（セキュリティ・週次リサーチ等）/ Haiku バッチ系）に従う
4. **フォールバック**: halted 検出時の degrade 経路。多くは `recover_halted.sh` か、人間着手提案、または次サイクル待機

### 2. 入力サイン → ペルソナ ディスパッチ表

#### 2.1 Linear イベント駆動

| 入力サイン | ペルソナ | プライマリ モデル | フォールバック |
|---|---|---|---|
| 新規 GitHub Issue | `kobaamd_sync_github` | Sonnet | リトライ 3 回 → 次回 daily |
| draft → backlog 昇格要求 | `kobaamd_create_prd` | Sonnet | Anthropic halted: 次サイクル待機 |
| backlog → todo（人間承認） | （手動 or `assign_work` 検出） | — | — |
| todo の new issue（WIP=1 空き） | `kobaamd_assign_work` → `kobaamd_implement_code` | Sonnet + Codex | Codex 429: KMD-123 共通ハンドラで指数バックオフ → 限界で `[halted-codex]` ラベル付与し人間着手提案 |
| in Review の PR (機能 review) | `kobaamd_review_pr` | Sonnet | Anthropic halted: PR を `[review-pending-halted]` ラベル付与、次サイクルで再走 |
| in Review の PR (セキュリティ review、並行) | `kobaamd_review_security` | Opus（誤判定の代償大、最後の砦として Opus 維持） | Anthropic halted: PR を `[review-pending-halted]` ラベル付与、次サイクルで再走 |
| in Review の REQUEST_CHANGES | `kobaamd_fix_pr_comments` | Sonnet | リトライ 3 回 |
| Human in Review の人間コメント | `kobaamd_rework_issue`（5 カテゴリ分類） | Sonnet | 5 カテゴリ分類自体は Haiku でも可、本作業 rework は Sonnet |
| Human in Review の `carve` 指示 | `kobaamd_carve_concerns` | Sonnet | リトライ 3 回 |
| Reviewed への遷移 | `kobaamd_merge_pr` | Sonnet | コンフリクト時は `In Progress` 戻し → `kobaamd_implement_code` リカバリ |
| Done への遷移 | `kobaamd_review_postmortem` → `kobaamd_update_wiki` | Sonnet | 失敗時はスキップ、update_wiki は次回 weekly に持ち越し |

#### 2.2 パイプライン定期起動

| トリガー | 起動するロール | プライマリ モデル | フォールバック |
|---|---|---|---|
| `pipeline_active`（30 分） | フェーズ A → フェーズ B（最大 5 サイクル） | Mixed | step 0c で `recover_halted.sh --auto` が halted PR を検出して復帰 |
| `pipeline_daily`（8:00） | `health_check` → `archive_done` → `detect_stale` → `sync_github` | Sonnet 主体 | health_check が CRITICAL を検出すれば `[infra/health]` issue 起票、後続続行 |
| `pipeline_weekly`（月 9:00） | `research_create_ticket` → `report_status` → `summarize_changelog` → `improve_prompt` → `update_wiki` | Mixed: research_create_ticket / improve_prompt は Opus（創造性・週次低頻度のため例外）、その他は Sonnet | 各ステップ独立、失敗時は次に進む |

#### 2.3 transcript の人間入力（メインセッションでの会話）

| 入力サインの例 | ペルソナ | プライマリ モデル | フォールバック |
|---|---|---|---|
| 「マージして OK」「Reviewed にして」 | メインセッション → `kobaamd_merge_pr` | Opus → Sonnet | User Intent 不足ならコメント確認のみ |
| 「PRD 作って」「KMD-XX を backlog に」 | `kobaamd_create_prd` | Sonnet | — |
| 「コードレビューして」「PR #N 見て」 | `kobaamd_review_pr` | Sonnet | Anthropic halted: 概要のみ手動レビューに degrade |
| 「ビルド通った？」「テスト走らせて」 | `kobaamd_validate_build` | Sonnet | — |
| 「なぜこの設計？」「どう思う？」 | メインセッション直で議論 | Opus | 設計判断は委譲しない |
| 「実装して」「この機能を追加」 | `kobaamd_implement_code` | Sonnet + Codex | Codex 不可: メインセッションが Codex プロンプト案だけ提示し人間着手依頼 |
| 「この shell スクリプトを 30 行未満で直して」 | メインセッション直で Edit | Opus | 30 行超 / 構造変更 → `kobaamd_implement_code` 経由（§4 行参照） |
| 「ドキュメント書いて」「ADR 作って」 | Gemini 経由 | Gemini | Gemini 不可: メインセッションが下書き → 人間レビュー |
| 緊急 hotfix（infra / 起動不能等） | メインセッション直で PR | Opus | 即応性優先 |
| 「振り返って」「learnings 書いて」 | `kobaamd_review_postmortem` | Sonnet | — |
| 「wiki 更新して」 | `kobaamd_update_wiki` | Sonnet | — |

### 3. 人間コメントの 5 カテゴリ分類（再掲）

`Human in Review` の人間コメントは複数カテゴリが共存しうる。`pipeline_active` ステップ 4 で機械的に分類してから対応ペルソナに振り分ける。**正本は `.claude/commands/kobaamd_pipeline_active.md`**:

| カテゴリ | キーワード | 起動するロール |
|---|---|---|
| **approval** | 「マージして」「OK」「承認」 | `Reviewed` 遷移 → `kobaamd_merge_pr` |
| **carve** | 「別チケット」「分けて」「後で」 | `kobaamd_carve_concerns` |
| **rework_spec** | 仕様変更・追加要件 | `kobaamd_rework_issue` |
| **rework_impl** | 実装の修正指示 | `kobaamd_rework_issue` または `kobaamd_fix_pr_comments` |
| **question** | 質問・確認 | コメント返信のみ、ステータス維持 |

処理順: **carve → rework → approval → question**。詳細は [[autonomous-pipeline-philosophy]] と [[concern-carve-out]]。

### 4. 近接ロールの境界

| 境界 | 判定基準 |
|---|---|
| `kobaamd_rework_issue` vs `kobaamd_fix_pr_comments` | **仕様変更を含むなら rework**、コードレベルの修正のみなら fix_pr_comments。人間コメント駆動なら rework、自動レビュー駆動なら fix_pr_comments |
| `kobaamd_create_prd` vs `kobaamd_research_create_ticket` | 入力ステータスで分岐: draft → backlog なら create_prd、新規発掘 → backlog なら research_create_ticket |
| メインセッション直 vs `kobaamd_implement_code` | 緊急 hotfix / 設定 1 ファイル変更はメインセッション直。複数ファイル / SwiftUI コア変更は implement_code 経由（Codex に依頼） |
| **shell script (`*.sh`) 小規模 fix vs Codex CLI** | **30 行未満 / 構造変更なし**（surgical fix）はメインセッション直で Edit 可。30 行超 / 関数構造の大幅変更 / 複数 shell ファイル横断はは `kobaamd_implement_code` 経由（Codex CLI）。CLAUDE.md 役割分担表は「`.swift` は Codex」と書いているがこれを `*.sh` には機械適用しない。実例: KMD-153（`scripts/wiki/lib/section-context-check.sh` で 17 行追加 / 2 行変更の stdout/stderr 分離）はメインセッション直で 23 分の能動フェーズで完了 |
| `kobaamd_review_pr` vs メインセッション直 | 自律パイプライン PR は review_pr。メインセッションが手動で出した PR は **どちらでもよいが、結果として Human in Review を経由** |
| `kobaamd_health_check` vs `kobaamd_report_status` | 死活監視（即時検知）は health_check（daily）、傾向分析（俯瞰）は report_status（weekly） |

### 5. モデル選択の 2 段階運用（節約 + 品質）

[[wiki-reference-policy]] の Phase 1 標準を踏まえ、**一次トリアージは Haiku、本作業は Opus/Sonnet** の 2 段階で考える。

| ステップ | モデル | 役割 |
|---|---|---|
| 一次トリアージ・分類 | **Haiku**（必須ルール 4 項目を満たす） | 5 カテゴリ分類、健康診断ログの集計、軽量バッチ |
| 機械的操作 | **Sonnet** | ビルド検証、マージ操作、定型修正 |
| 判断・創造・分析 | **Opus** | 設計判断、PRD 創造、批判レビュー、振り返り |

Haiku の必須 4 項目: Prompt Caching / バッチ / no-op フォールバック / content_hash 差分。詳細は [[wiki-reference-policy]] §4。

### 6. halted 検知と degrade 経路

#### 6.1 halted の主な発生パターン

| パターン | 検知方法 | 対処 |
|---|---|---|
| **Anthropic 月次 usage limit** | `org's monthly usage limit` メッセージ | step 0c の `recover_halted.sh` が WIP commit + `[halted-recovered]` ラベル付与 |
| **Codex 429 / quota** | `codex exec` の stderr に rate / quota メッセージ | KMD-123 共通ハンドラで指数バックオフ。限界で `[halted-codex]` ラベル + 人間着手提案 |
| **Gemini API エラー** | curl の HTTP ステータス | UI/UX 検証はスキップ、機能観点のみで継続（[[concern-carve-out]]） |
| **launchd EX_CONFIG** | `launchctl print` で `last exit code != 0` | `health_check` が検出 → `[infra/health]` issue 起票 → 人間が `install.sh` 再実行 |
| **pipeline_active hang** | `kobaamd_pipeline_active.log` に start のみで end がない | `health_check` の警告 → 次回起動で自然回復、長時間続けば issue 起票 |

#### 6.2 halted リカバリの設計（PR #59 で実装済み）

1. **WIP commit 義務化**: `kobaamd_implement_code` / `rework_issue` / `fix_pr_comments` が swift build パス直後に commit + push（`--no-verify` 禁止）
2. **`scripts/recovery/recover_halted.sh`**: halted 状態を自動検出 → commit → push → PR 作成 → Linear に `[halted-recovered]` ラベル付与
3. **pipeline_active step 0c**: 上記スクリプトの `--auto` 起動を組み込み、起動毎に halted PR を救済

#### 6.3 事前 usage チェック（KMD-128 計画中）

`pipeline_active` の冒頭で過去 5 時間の API 呼び出しを集計し、閾値超過時に Phase B（新規実装）をスキップする予防策:

- `.logs/api_usage.jsonl` に各 API call を `{ts, api, type, est_tokens}` で append
- 閾値（仮）: Claude > 100 call / 5h、Codex > 50 call / 5h、Gemini > 30 call / 5h
- スキップ時は KMD-117 epic にコメント記録
- Phase A（既存 PR の merge / fix_pr_comments）は継続

### 7. 入力サインの判定ヒューリスティクス（メインセッション向け）

```
Step 1: 入力に Linear KMD-XX が含まれるか？
  Yes → 該当 issue の現在ステータスを取得し、§2.1 の表を引く
  No  → Step 2

Step 2: 入力に PR 番号が含まれるか？
  Yes → PR と紐づく KMD-XX を解決し、§2.1 の表を引く
  No  → Step 3

Step 3: 入力が「マージ」「承認」「Reviewed に」を含むか？
  Yes → User Intent Rule で transcript 明示を要求するパターンか確認 → kobaamd_merge_pr
  No  → Step 4

Step 4: 入力が新機能 / 新タスクを示唆するか？
  Yes → §2.3 の表を引く（PRD 作成 / 実装 / レビューのいずれか）
  No  → Step 5

Step 5: 入力が議論・質問なら、メインセッション直で対応
```

判定に迷う場合は **「ペルソナを選ぶ前にまず入力を 1 行で要約してから表を引く」** ことを推奨。

### 8. Phase A コスト最適化との連動

KMD-118 配下の 5 案は本辞書のディスパッチに直接効く（実装後に本記事を更新する）:

| チケット | 改善点 | 本辞書への影響 |
|---|---|---|
| KMD-119 | `pipeline_active` no-op early return | §2.2 で「対象 issue がないときの早期復帰」をフローに追加 |
| KMD-120 | subagent から CLAUDE.md 重複 Read 削除 | §5 の「Wiki 参照は ask.sh 経由のみ」を強制化 |
| KMD-121 | Wiki 参照を `scripts/wiki/ask.sh` 経由に統合 | §5 の Prompt Caching 前提を全 subagent で標準化 |
| KMD-122 | review_pr の Gemini 呼び出しを Linear コメント履歴で機械ゲート化 | §6.1 の Gemini halted 対応に「重複呼び出し抑制」を追加 |
| KMD-123 | Codex 429 ハンドリングを 3 subagent 共通化 | §6.1 の Codex 429 行が共通ハンドラ前提に変わる |

### 9. 本記事の運用ルール

- **更新タイミング**: 新 subagent 追加時 / モデル割当変更時 / halted パターン追加時 / Phase A 着手完了時
- **更新者**: `kobaamd_update_wiki` が learnings / postmortem からの差分を反映、または手動で追記
- **重複排除**: §10 SSOT ルールに従う
- **Prompt Caching**: 本記事も `docs/wiki/articles/` 配下なので、`scripts/wiki/ask.sh` 経由で全 subagent に共有される

### 10. Single Source of Truth (SSOT) ルール

複数箇所に方針が散在すると、編集時の同期漏れや矛盾が発生する。以下の正本マッピングを徹底する:

| 領域 | 正本 | 派生（参照のみ） |
|---|---|---|
| ステータスフロー / 人間承認ゲート | `CLAUDE.md`（運用ガイド） | `[[autonomous-pipeline-philosophy]]` で要約 |
| モデル割当（Opus/Sonnet/Haiku） | `[[wiki-reference-policy]]` §3-4 | 本記事 §5、`[[team-structure]]` 末尾 |
| Phase 移行トリガー（Prompt Caching） | `[[wiki-reference-policy]]` §2 | `kobaamd_health_check.md` の監視ステップ |
| Linear I/O ポリシー | `CLAUDE.md`「Linear I/O ポリシー」 | 各 subagent の `## Linear I/O` 節 |
| 5 カテゴリ分類 | `.claude/commands/kobaamd_pipeline_active.md` ステップ 4 | 本記事 §3 で要約 |
| 各 subagent の責務 | `.claude/agents/<name>.md` の `description:` | `[[team-structure]]` で一覧化 |
| 外部依存（API キー / 認証） | `[[external-teams]]` | `CLAUDE.md` の「APIキー」節 |
| concern 3 分類 | `[[concern-carve-out]]` | 本記事 §3 で要約 |
| halted リカバリ機構 | `scripts/recovery/recover_halted.sh` + PR #59 commit | 本記事 §6.2 + `[[team-structure]]` 末尾 |

**派生記事の編集ルール**:
- 「正本を参照」する形式に統一（`[[wiki-link]]` または相対リンク）
- 詳細を派生にコピペしない（要約 + 参照リンクで止める）
- 正本が変わったら派生は自動的に古くなる前提で、派生記事のヘッダ `updated:` を見て stale 判定
- `kobaamd_update_wiki` の差分検知時に正本 → 派生の同期漏れを警告（将来実装、`kobaamd_lint_wiki` で stale 検知済）

**SSOT 違反パターン**:
- 同じ詳細表が複数記事に存在する（コピペ）→ 1 つに集約 + 残りは参照
- 派生記事が正本より新しい記述を持つ → 正本に逆流させる
- 正本の場所が記事内に書かれていない → 各記事の Sources / Related 節で必ず明記

### 11. wiki 記事の永続化ルール（消失防止）

`team-structure.md` / `external-teams.md` は 2026-05-01 と 2026-05-06 の 2 回、git stash 操作またはバックグラウンド処理で消失した。同様の事故を防ぐため:

1. **作成と同時に commit**: 新規記事 / 大幅編集後は、その回の作業内で `git add docs/wiki/articles/<file> docs/wiki/index.md docs/wiki/log.md` をまとめて commit する。次タスクに移る前に commit を確認
2. **pre-push hook の警告に従う**: `scripts/hooks/pre-push` が `docs/wiki/articles/` の untracked / modified を警告する。push 前に必ず確認
3. **stash する前に wiki 変更を分離**: 作業中ブランチで wiki 編集が混在する場合、wiki だけ先に commit してから stash する（stash 内容の取り違えで消失する）
4. **メインセッションが wiki を作るときの遵守**: 記事作成 → index/log 更新 → commit を 1 サイクルで完結させる
5. **バックグラウンド処理との競合回避**: pipeline_active 等が走っている可能性のあるときは、新規 wiki 作業前に `pgrep -lf kobaamd_pipeline` で稼働状況を確認

## Related

- [[team-structure]] — コアチームの組織図（誰がいるか）
- [[external-teams]] — 外部依存（何と接続しているか）
- [[wiki-reference-policy]] — モデル割当 + Prompt Caching の正本
- [[multi-llm-persona]] — LLM 役割割当ポリシー
- [[autonomous-pipeline-philosophy]] — パイプライン全体の設計思想
- [[concern-carve-out]] — review_pr の concern 3 分類
- [[postmortem-patterns]] — パターン 12（APPROVE 後 carve-out 必須）など本辞書の根拠

## Sources

- `docs/wiki/articles/practices/team-structure.md`
- `docs/wiki/articles/practices/wiki-reference-policy.md`
- `docs/wiki/articles/practices/external-teams.md`
- `docs/wiki/articles/decisions/multi-llm-persona.md`
- `.claude/commands/kobaamd_pipeline_active.md`（5 カテゴリ分類の正本）
- `scripts/recovery/recover_halted.sh`（PR #59 で実装）
- KMD-117（epic）、KMD-118（PR-A 親）、KMD-119〜123（Phase A 子チケット）、KMD-128（PR-B4 事前 usage チェック）
- `docs/handoff/2026-05-06-cost-optimization-prompt.md`
- docs/learnings/2026-05-08-KMD-153.md（shell script 小規模 fix の経路、実例: PR #84）
