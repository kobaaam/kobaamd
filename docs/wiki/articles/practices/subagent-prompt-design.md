---
title: subagent プロンプト設計（Claude Code 暗黙注入を踏まえた）
category: practices
tags: [subagent, prompt-design, claude-code, context-injection, cost-optimization, defense-in-depth]
sources:
  - docs/learnings/2026-05-08-KMD-120.md
created: 2026-05-08
updated: 2026-05-08
---

# subagent プロンプト設計（Claude Code 暗黙注入を踏まえた）

## Summary

Claude Code は subagent 起動時に CLAUDE.md / README.md などを system context へ暗黙注入する。subagent プロンプトでこれらを明示 Read すると重複注入でトークンを浪費する。KMD-120 (PR #76) では 5 subagent から明示 Read を削除して ~480k tokens/日の削減を狙うとともに、削除によるルール風化を防ぐため Constraints セクションを格上げした defense-in-depth を組み込んだ。本記事はその設計原則を kobaamd の subagent プロンプト標準としてまとめる。

## Content

### 1. Claude Code の暗黙コンテキスト注入境界
<!-- llm-context: subagent プロンプトを書くときに「Claude Code 側で session に既に注入されているファイル」と「subagent が能動的に Read すべきファイル」を見分けるための境界判定ルール。 -->

Claude Code は subagent 起動時に system context として `CLAUDE.md` / `README.md` 等の standard knowledge ファイルを自動展開する。これは subagent プロンプトに `Read CLAUDE.md (always)` のような明示記述を書くと、Claude Code 側の暗黙注入と subagent の Read tool 呼び出しが二重に発生することを意味する。

kobaamd では 1 subagent あたり ~8k tokens の CLAUDE.md が複数 subagent から重複 Read されており、KMD-120 ではこれを 5 subagent ぶん（research_create_ticket / create_prd / implement_code / review_pr / review_security）削除することで ~480k tokens/日 規模の削減を狙った。

### 2. 削除する / 残す の判断基準

subagent プロンプトでの明示 Read を **削除する**（暗黙注入に任せる）対象:

- リポジトリルートの `CLAUDE.md`
- リポジトリルートの `README.md`
- `~/.claude/CLAUDE.md`（global instructions）
- `MEMORY.md` 等、Claude Code が session memory として展開するファイル

明示 Read を **残す**（暗黙注入されないため subagent が能動取得すべき）対象:

- `Sources/**/*.swift`（実装一次資料）
- `.claude/agents/*.md` / `.claude/commands/*.md`（subagent / slash 定義の自己参照）
- `docs/wiki/articles/**/*.md`（標準は `scripts/wiki/ask.sh` 経由でまとめて参照）
- `docs/learnings/*.md`、`docs/adr/*.md`（postmortem / ADR）
- `docs/handoff/*.md`（一時引き継ぎ文書）
- ジョブ実行時の入力 issue / PR diff（Linear / GitHub から取得）

判断のヒューリスティクスは「リポジトリルート直下にあり Claude Code が `claudeMd` として展開している＝削除、それ以外で能動取得が必要＝残す」。

### 3. defense-in-depth: Constraints セクションの格上げ
<!-- llm-context: 明示 Read を削除しただけでは、subagent が CLAUDE.md のルールを「読んだ気」になっているのに具体指示が見えなくなり風化する。Constraints セクションで責務境界を再明示することで暗黙注入が万一漏れても subagent 単体で正しく動く設計にする。 -->

明示 Read を削除すると、subagent プロンプトの本文から CLAUDE.md のルール（Codex 経由鉄則・Linear I/O ポリシー・Hardened Runtime 不変条件など）が直接見えなくなる。暗黙注入が機能している間は問題ないが、注入境界が変わったり Claude Code のバージョンが更新されたりすると subagent がルールを失う。

KMD-120 では 5 subagent すべての Constraints セクションで、暗黙注入に頼らず subagent 単体で完結する責務境界を明示した:

- `kobaamd_implement_code`: 「Swift 実装は必ず Codex CLI 経由」「`Sources/` に踏み込む必要が出たら implement_code に差し戻す」
- `kobaamd_research_create_ticket`: 「learnings に Action Items として書き implement_code に委ねる」
- `kobaamd_create_prd` / `kobaamd_review_pr` / `kobaamd_review_security`: 各 subagent の責務境界（PRD 作成・レビュー観点・セキュリティ観点）を再明示

これにより「session context が万一注入されなくても subagent 単体で正しく動く」設計に寄せ、トークン削減と引き換えにルール記憶を弱める懸念を defense-in-depth で抑え込んだ。

### 4. subagent MD 編集時の整合性チェックリスト

`.claude/agents/*.md` は frontmatter（`description:` / `tools:` / `model:`）と本文（Workflow / Constraints / Final Report Format）の二重構造を持つ。本文だけ更新して frontmatter が取り残されると、Linear や `kobaamd_assign_work` 等の派生処理が古い `description:` を参照する。

KMD-120 では implement_code が本文の Workflow / Constraints 更新に集中し、frontmatter `description:` の整合まで行き届かず auto-carve（KMD-156）対象になった。再発防止として `kobaamd_implement_code` の Constraints に「subagent 定義 MD を変更する場合、frontmatter と本文の整合をセットでチェック」を追記する運用を取る。詳細は [[postmortem-patterns]] パターン 16 を参照。

### 5. 観測前提の AC は観測手段もセットで設計する

KMD-120 PRD の AC 4 項目目「次回 postmortem で Karpathy Guidelines / 命名規則違反が発生していないことを確認」「input token 数の削減を観測」は観測前提だが、launchd ログから input token を集計するスクリプトは未整備で、本 postmortem 時点でも定量検証ができていない（~480k tokens/日 削減は推算）。

教訓: 観測前提の AC を含む PRD は、観測手段（集計スクリプト・ログ抽出方法）の整備を **同 PR の影響範囲または別チケット** として明記する。`kobaamd_research_create_ticket` / `kobaamd_create_prd` のプロンプトで観測前提 AC を検出した場合、観測手段の起票も併せて提案する運用が望ましい。本パターンは [[postmortem-patterns]] パターン 17 と [[prd-quality-cycle]] にも反映する。

### 6. KMD-120 の運用結果（参照実例）
<!-- llm-context: 「subagent プロンプトから明示的な `Read CLAUDE.md` 行を削除して入力トークンを削減する」という KMD-120 タスクの実装結果サマリ。AC が実測前提だった点や、リードタイム・auto-carve 経路を、本記事の subagent プロンプト設計原則 1〜5 を裏付ける実例として並べたセクション。 -->

- **対象 5 subagent**: `kobaamd_implement_code` / `kobaamd_create_prd` / `kobaamd_research_create_ticket` / `kobaamd_review_pr` / `kobaamd_review_security`
- **明示 Read 行の実在件数**: 5 ファイル中 2 ファイルのみ（`kobaamd_create_prd` と `kobaamd_research_create_ticket`）。残り 3 は元々無く no-op
- **AC が実態前提でなかった**ため、実装段階で「2/5 のみ該当・残り 3 は session-context 前提の文言追加 + Constraints 補強で対応」と PR / Linear に透明開示するコメントを残した
- **review_pr の判定**: 残 concern 1 件（frontmatter `description:` の整合）を auto-carveable と分類し KMD-156 に退避、親 PR は Reviewed 直行 → merge_pr で自動マージ
- **リードタイム**: 実装〜マージ 8 分、リワーク 0 回。Backlog 起票から Todo 昇格まで 2.6 日（人間承認ゲート待ちが支配的）

`scripts/wiki/ask.sh` 経由の wiki 全件投入は引き続き Prompt Caching の標準経路として残す（[[wiki-reference-policy]] §1）。本記事の主題は **wiki 参照ではなく subagent プロンプト本体に書く明示 Read 行** の削除であり、両者を混同しない。

## Related

- [[postmortem-patterns]]
- [[prd-quality-cycle]]
- [[autonomous-pipeline-philosophy]] — concern を auto-carveable と判定する 3 条件（動作影響なし / AC 範囲外 / 独立修正可）。KMD-120 の frontmatter `description:` 整合不備が 3 条件全充足で KMD-156 に auto-carve された経路

## Sources

- docs/learnings/2026-05-08-KMD-120.md
- KMD-120（[PR-A2] subagent から CLAUDE.md の明示 Read を削除）
- KMD-156（auto-carved-out by kobaamd_review_pr、frontmatter description 整合）
- KMD-117（コスト最適化 + halted リカバリ epic）、KMD-118（PR-A 親）
