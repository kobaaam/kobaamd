---
title: PRD 品質基準と改善サイクル
category: practices
tags: [prd, review, quality, pipeline, impact-map]
sources:
  - docs/learnings/2026-04-28-KMD-4.md
  - docs/learnings/2026-04-28-KMD-6.md
  - docs/learnings/2026-04-29-KMD-20.md
  - docs/learnings/2026-05-05-KMD-54.md
created: 2026-04-30
updated: 2026-05-06
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

### 影響範囲マップ（PRD section 8）の効能 — KMD-54 事例
<!-- llm-context: PRD section 8 に「変更してはいけない箇所」を防御的に書くことで、AI レビュー観点が独立評価可能になり、Human in Review を経由せずクリーン APPROVE 直行できることを示した事例。 -->

KMD-54（pipeline_weekly に lint_wiki を組み込み）では、PRD section 8 に **変更対象 3 ファイル + 変更禁止ファイル一覧（Swift / plist / Package.* など）** を明文化した。これにより:

- `kobaamd_review_pr` の観点判定が「マップ通り 3 ファイルのみ変更」「マップ外への手出しなし」を独立評価できた
- implement 側もマップに従う動機が強くなり（後で review_pr に指摘される）、レビューが一発で通った
- 結果としてリワーク 0 回・Todo → Done 約 17 分でクリーン APPROVE 直行を達成

加えて section 8「その他リスク」に **依存逆順耐性のためのガード**（依存先 lint.sh 不在時の skip）を予め書き込んでおいたことで、レビュー側もこれを観点として pass 判定できた。詳細は [[dependency-inversion-guard]] を参照。

## Related

- [[autonomous-pipeline-philosophy]] — パイプライン全体の思想
- [[postmortem-patterns]] — 具体的な再発防止パターン（クリーン APPROVE 直行 4 条件を含む）
- [[wiki-reference-policy]] — wiki 参照を含む PRD/設計知見の運用標準
- [[dependency-inversion-guard]] — section 8 で書く依存逆順ガードのテンプレート

## Sources

- docs/learnings/2026-04-28-KMD-4.md
- docs/learnings/2026-04-28-KMD-6.md
- docs/learnings/2026-04-29-KMD-20.md
- docs/learnings/2026-05-05-KMD-54.md
