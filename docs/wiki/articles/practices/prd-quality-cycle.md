---
title: PRD 品質基準と改善サイクル
category: practices
tags: [prd, review, quality, pipeline]
sources: [docs/learnings/2026-04-28-KMD-4.md, docs/learnings/2026-04-28-KMD-6.md]
created: 2026-04-30
updated: 2026-04-30
---

# PRD 品質基準と改善サイクル

## Summary

10セクション PRD テンプレートと review_prd ↔ create_prd の自動修正ループで品質を担保。KMD-4/6 の postmortem から「PRD のスコープ曖昧さが実装リワークを増やす」ことを学んだ。

## Content

### 10セクション品質バー

| セクション | 不合格条件 |
|-----------|-----------|
| 5 UI/UX | ASCII ワイヤーなし、抽象表現のみ |
| 6 AC | 3件未満、主観的、観察不能 |
| 7 テスト戦略 | 具体ファイルパスなし |
| 8 リスク | 具体ファイル名なし |

### レビュー↔修正ループ

`pipeline_active` ステップ 6 で自動実行:
1. `review_prd` が PASS / REQUEST_REVISION を判定
2. REQUEST_REVISION → `create_prd` が修正モードで再実行（レビューコメントを読み取り）
3. 最大5回ループ、超過時は人間エスカレーション

### KMD-4/6 の教訓

- KMD-4: 9回のリワーク。PRD のスコープ記述が曖昧で Codex が範囲外の変更を繰り返した
- KMD-6: 13回のリワーク。同じパターンが再発。影響範囲マップ（変更禁止ファイル一覧）の必須化で改善

### KMD-20 で改善を確認

影響範囲マップを PRD に明記した結果、リワーク 0 回でマージ成功。

## Related

- [[autonomous-pipeline-philosophy]] — パイプライン全体の思想
- [[postmortem-patterns]] — 具体的な再発防止パターン

## Sources

- docs/learnings/2026-04-28-KMD-4.md
- docs/learnings/2026-04-28-KMD-6.md
- docs/learnings/2026-04-29-KMD-20.md
