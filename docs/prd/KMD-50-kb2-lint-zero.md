---
issue: KMD-50
title: KB2 Wiki Lint violations を 0 件に（残作業）
status: implementing
created: 2026-05-09
---

# KMD-50 KB2 Wiki Lint violations を 0 件に（残作業）

## 1. 目的

KMD-50 メタチケットの AC のうち未充足な「既存 articles の Lint エラーが 0 件まで修正される」を達成する。現在 `scripts/wiki/lint.sh --no-llm` が 13 violations を出している状態を、0 件にする。

## 2. 現状（残違反 13 件）

### broken-link (4 件) — `[[concern-carve-out]]` 未解決

- `docs/wiki/articles/practices/role-dispatch.md` line 87, 120, 226
- `docs/wiki/articles/practices/team-structure.md` line 107

### related-asymmetric (9 件) — Related 双方向リンク不足

- `external-teams.md` ↔ `decisions/autonomous-pipeline-philosophy.md`
- `external-teams.md` ↔ `practices/sparkle-release.md`
- `external-teams.md` ↔ `practices/security-hardening.md`
- `external-teams.md` ↔ `practices/wiki-reference-policy.md`
- `role-dispatch.md` ↔ `practices/wiki-reference-policy.md`
- `role-dispatch.md` ↔ `decisions/multi-llm-persona.md`
- `team-structure.md` ↔ `decisions/multi-llm-persona.md`
- `team-structure.md` ↔ `decisions/autonomous-pipeline-philosophy.md`
- `team-structure.md` ↔ `practices/wiki-reference-policy.md`

## 3. 解決方針

### 3.1 broken-link の解決

`docs/wiki/articles/practices/concern-carve-out.md` を **新規作成**する。`concern-carve-out` は既に以下で言及・運用されており SSOT 記事を作るに足る規模:

- `.claude/commands/kobaamd_carve_concerns.md`（slash command 実装、195 行）
- `[[postmortem-patterns]]` パターン 7 / 13 / 18 / 19 / 20
- `[[role-dispatch]]` §3 概要、§10 SSOT 表
- `[[autonomous-pipeline-philosophy]]` の APPROVE 直行 4 条件

すでに **複数の wiki 記事と slash command** が `[[concern-carve-out]]` を SSOT として参照することを前提に書かれているので、新規記事を立てるのが最も干渉の少ない解決策となる（既存 `[[wikilink]]` 11 箇所を一斉 inline 化するよりリスクが小さい）。

### 3.2 related-asymmetric の解決

リンク先の `## Related` に `[[元記事]]` を 1 行ずつ追加する。

## 4. 受け入れ条件

- [ ] `scripts/wiki/lint.sh --no-llm` 実行時に `violations=0` になる
- [ ] 新規 `concern-carve-out.md` が SCHEMA に準拠する（frontmatter 完備、Summary / Content / Related / Sources を持つ）
- [ ] index.md に新規記事行が追加される
- [ ] log.md に ingest 記録が追記される
- [ ] swift コードへの変更は **無し**（wiki / docs 専用）

## 5. 制約

- swift コードを変更しない（wiki / docs のみ）
- swift build / swift test の検証は不要（変更が docs 配下のみ）
- 双方向 Related は **対称的に 1 行ずつ追加**するだけにとどめ、無関係な記事の追記は行わない
- frontmatter `updated:` は変更したファイルのみ today (2026-05-09) に更新

## 6. 影響範囲マップ

### 変更対象ファイル（追加）

| ファイル | 変更内容 |
|---|---|
| `docs/wiki/articles/practices/concern-carve-out.md` | 新規作成（SSOT 記事、concern 3 分類 / carve-out 判断 / slash command 経路 / 運用上の罠を集約） |

### 変更対象ファイル（変更）

| ファイル | 変更内容 |
|---|---|
| `docs/wiki/articles/decisions/autonomous-pipeline-philosophy.md` | `## Related` に `[[external-teams]]`, `[[team-structure]]` 追加 |
| `docs/wiki/articles/decisions/multi-llm-persona.md` | `## Related` に `[[role-dispatch]]`, `[[team-structure]]` 追加 |
| `docs/wiki/articles/practices/wiki-reference-policy.md` | `## Related` に `[[external-teams]]`, `[[role-dispatch]]`, `[[team-structure]]` 追加（既存 2 件は維持） |
| `docs/wiki/articles/practices/sparkle-release.md` | `## Related` に `[[external-teams]]` 追加 |
| `docs/wiki/articles/practices/security-hardening.md` | `## Related` に `[[external-teams]]` 追加 |
| `docs/wiki/index.md` | Practices セクションに `concern-carve-out.md` 行追加 |
| `docs/wiki/log.md` | `[2026-05-09] Wiki KB2 lint zero` セクションを末尾に追記 |

### 触れてはいけない箇所

- `docs/wiki/articles/practices/role-dispatch.md` — 既存記事の `[[concern-carve-out]]` を inline 化 **しない**（SSOT 参照を維持）
- `docs/wiki/articles/practices/team-structure.md` — 同上、line 107 の `[[concern-carve-out]]` を inline 化 **しない**
- 本タスク対象外の articles（`postmortem-patterns.md` / `prd-quality-cycle.md` 等）の Related や本文を編集しない
- swift / scripts / .claude/ 配下のファイル（lint 違反とは無関係）
- 既存記事の本文 / 見出し構造 / Summary / Sources（Related 1 行追加と `updated:` 日付以外は触らない）

## 7. 検証手順

```bash
./scripts/wiki/lint.sh --no-llm
# violations=0 であること
```

## 8. リスク

- 新規 `concern-carve-out.md` が他記事と SSOT 重複する場合、後で `kobaamd_review_pr` の concern として「SSOT 違反」と指摘される可能性がある。今回の記事は role-dispatch §3 と postmortem-patterns パターン 7 / 13 を **要約参照する** 形式に留め、詳細記述は元記事側を正本とする
- 双方向化で記事数が膨らむと「弱関連の Related」が増える懸念。Related 追加は **lint 違反の解消に必要な分のみ**にとどめる
