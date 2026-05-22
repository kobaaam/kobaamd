---
title: concern carve-out（PR レビュー懸念の 3 分類と別チケット退避）
category: practices
tags: [concern, review-pr, carve-out, pipeline, ssot, human-in-review]
sources: [.claude/commands/kobaamd_carve_concerns.md, docs/wiki/articles/practices/postmortem-patterns.md, docs/wiki/articles/practices/role-dispatch.md, docs/wiki/articles/decisions/autonomous-pipeline-philosophy.md, CLAUDE.md]
created: 2026-05-09
updated: 2026-05-23
---

# concern carve-out（PR レビュー懸念の 3 分類と別チケット退避）

## Summary

`kobaamd_review_pr` が PR diff を批判レビューしたときに残る「concern」を、本 PR で直すか・別チケットに退避するか・人間判断を仰ぐかに **機械的に 3 分類**するルールと、別チケット化（carve-out）の運用手順を集約した SSOT 記事。`Reviewed` 直行 / `Human in Review` 滞留 / 別 PR への退避の境界を一枚で説明する。

3 分類の正本ルール：本記事。具体運用：[[role-dispatch]] §3 と `[[postmortem-patterns]]` パターン 7 / 13 / 18 / 19 / 20。slash command 実装：`.claude/commands/kobaamd_carve_concerns.md`。

## Content

### 1. 背景

`kobaamd_review_pr` の concern を一律に「本 PR で直す」前提にすると、`Human in Review` に PR が滞留してリードタイムが伸び、自律パイプラインのスループットが落ちる。一方、すべて別チケットに退避すると「AI が責務を逃れている」ように見える。`concern` を **本 PR で扱うか・別 PR で扱うか・人間判断に委ねるか** を機械的に振り分けるのが本ルールの目的。

### 2. concern の 3 分類

`kobaamd_review_pr` は各 concern を以下の 3 カテゴリに分類してから遷移先を決める。

| 分類 | 定義 | 遷移先 |
|---|---|---|
| **rework** | 本 PR の AC・PRD section 8 影響範囲・PRD 非ゴール のいずれかに直接抵触する concern。本 PR 内で直さないと AC 未達 | `In Progress` に戻し `kobaamd_fix_pr_comments` ループ |
| **auto-carveable** | PR の主目的と独立した改善（テスト整備・observability 強化・UI 磨き込み・無関係なリファクタ案）。本 PR を block する必要がない | 自動で別 issue 起票（`kobaamd_carve_concerns`）→ 親はクリーンとして `Reviewed` 直行 |
| **human-judgment** | 仕様判断・設計判断が必要（PRD で言及されていない仕様追加 / トレードオフのある設計選択） | `Human in Review` に入れて人間コメントを待つ |

`fail` 判定（=「明らかな機能破壊」「AC が満たされていない」）は **3 分類の外** に置き、`fail>0` は無条件で `In Progress` 戻し（`kobaamd_fix_pr_comments` 起動）となる。本記事のスコープは `fail=0 かつ concern>0` のとき。

### 3. auto-carveable の判定 3 条件

`auto-carveable` に分類できるのは以下 3 条件 **すべて** を満たすときのみ（[[postmortem-patterns]] パターン 13 で確立）:

1. **PR の主目的（PRD section 1 の目的・AC）と独立**: concern が「主目的の一部分の補強」ではなく、別ユースケース・別観点に対する独立提案である
2. **PRD section 8 影響範囲と矛盾しない**: PRD で「変更してはいけない箇所」と記載された領域に concern が踏み込まない
3. **`[BREAKING]` ラベルが PR に付いていない**: 破壊的変更のあるレビューは必ず `Human in Review` を経由する

3 条件のうち 1 つでも欠ける concern は `rework` または `human-judgment` に降格させる。

### 4. carve-out の起票運用（`/kobaamd_carve_concerns`）

別チケット化の slash command は `.claude/commands/kobaamd_carve_concerns.md`。要点:

- 起票先: Linear KMD team / `Backlog` 状態 / **priority 4 (Low)**（AI 起票は人間承認ゲートを priority/label で守る原則）
- ラベル: 既存挙動の不具合は `Bug`、磨き込み・最適化は `Improvement`、新機能は `Feature`。多くの review_pr concern は `Improvement`
- 統合可否: 関連が深い複数 concern は **1 チケットにまとめて起票** する（[[postmortem-patterns]] パターン 13 の統合チケット運用）
- 親 issue へのコメント: carve-out した KMD-XX 一覧と「親 PR 内対応推奨でスキップした concern」を同じコメントに残す
- 親 issue の状態整理: 親に rework / human-judgment が残っていなければ `Reviewed` 遷移を **API call まで実行**（コメントだけで終わらせない）

### 5. APPROVE 直行 4 条件（`Reviewed` に直行できるとき）

[[autonomous-pipeline-philosophy]] のクリーン APPROVE 直行ルールを再掲。以下 4 条件すべてを満たすと `Reviewed` 直行（`Human in Review` を経由しない）:

1. `fail=0`（機能破壊なし、AC 達成済み）
2. `rework=0`（本 PR で直すべき concern なし）
3. `human-judgment=0`（仕様・設計判断不要）
4. `[BREAKING]` ラベルなし

`auto-carveable` のみが残っている場合は本条件を満たすので、`kobaamd_carve_concerns` で別チケット化してから `Reviewed` 遷移可能。

### 6. 運用上の罠（postmortem 由来）

- **取り消しできる carve-out**（[[postmortem-patterns]] パターン 7）: AI が auto-carve した concern を人間が「本 PR で直すべき」と判断し直す経路を担保する。carve-out 先 issue の本文に「親 PR: KMD-XX」「該当 concern 引用」を必ず入れる
- **多段 auto-carve 連鎖**（パターン 18 / 19 / 20）: KMD-150 → KMD-153 → KMD-171 のように carve-out した issue に対するレビューでさらに carve-out が連鎖しうる。連鎖は妨げないが、各 carve-out が独立した auto-carveable 3 条件を満たすことを毎回検証する
- **観測機構変更時の smoke test**（パターン 18）: stderr / log / metric の中継・出力フォーマット変更は **同 PR で smoke test** を含めるのが原則。test を欠く concern は rework に分類されることが多い
- **review_security のゲート観点選択**（パターン 19）: 観測性回復のような小規模 PR にすべての security 観点を盲目適用すると過剰 concern を量産する。`kobaamd_review_security` のゲート観点は PR 本質に応じて選ぶ
- **共有インフラスクリプトの API 切り替えは full PR が必須**（[[postmortem-patterns]] パターン 25）: `scripts/wiki/ask.sh` のような複数 subagent から呼ばれるスクリプトの環境変数 / CLI interface を変更する場合、呼び出し元の更新を同 PR に含めるか切り出して別 PR にするかのどちらかのみ許容される。呼び出し元更新なしで API を変えると `kobaamd_review_pr` のコラテラルダメージ観点で **fail** になり in-review → in-progress 戻しが確定する（KMD-117 の実例）

### 7. 関連 slash / subagent

- `kobaamd_review_pr`: concern を 3 分類して遷移先を決める（本ルールの **読み手**）
- `kobaamd_carve_concerns`: auto-carveable concern を Linear に退避する slash command
- `kobaamd_rework_issue`: `Human in Review` の人間コメント（5 カテゴリ分類）に応じて再実装ループ
- `kobaamd_fix_pr_comments`: rework concern を Codex CLI で直し in-review に戻す

ロール × 入力サイン × halted フォールバックの 4 層辞書は [[role-dispatch]] を参照。

## Related

- [[role-dispatch]] — concern 3 分類が組み込まれた 4 層ディスパッチ辞書
- [[autonomous-pipeline-philosophy]] — クリーン APPROVE 直行 4 条件と auto carve-out フロー
- [[team-structure]] — carve_concerns / review_pr / rework_issue ロールの位置付け

## Sources

- `.claude/commands/kobaamd_carve_concerns.md`（slash command 実装）
- `docs/wiki/articles/practices/postmortem-patterns.md`（パターン 7 / 13 / 18 / 19 / 20）
- `docs/wiki/articles/practices/role-dispatch.md`（§3 5 カテゴリ分類、§10 SSOT 表）
- `docs/wiki/articles/decisions/autonomous-pipeline-philosophy.md`（APPROVE 直行 4 条件）
- `CLAUDE.md`「自律開発パイプライン (WIP)」「ステータスフロー」節
