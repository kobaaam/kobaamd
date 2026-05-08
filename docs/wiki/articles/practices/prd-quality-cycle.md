---
title: PRD 品質基準と改善サイクル
category: practices
tags: [prd, review, quality, pipeline, impact-map]
sources:
  - docs/learnings/2026-04-28-KMD-4.md
  - docs/learnings/2026-04-28-KMD-6.md
  - docs/learnings/2026-04-29-KMD-20.md
  - docs/learnings/2026-05-05-KMD-54.md
  - docs/learnings/2026-05-08-KMD-120.md
created: 2026-04-30
updated: 2026-05-08
---

# PRD 品質基準と改善サイクル

## Summary

10セクション PRD テンプレートと review_prd ↔ create_prd の自動修正ループで品質を担保。KMD-4/6 の postmortem から「PRD のスコープ曖昧さが実装リワークを増やす」ことを学んだ。

## Content

### 10セクション品質バー
<!-- llm-context: kobaamd の PRD テンプレート（`docs/prd/<KMD-XX>-<slug>.md`）が持つ 10 セクション構成のうち、`review_prd` が REQUEST_REVISION を出す代表的な不合格条件を 4 セクション分まとめた品質バー。 -->

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

### KMD-120 で見えた「観測 → 文言」AC の重要性
<!-- llm-context: PRD AC が「5 ファイルから X を削除」と仮説前提で書かれたが、実際に該当行が存在したのは 2 ファイルのみで、実装段階で透明開示の追加コストが発生したケースの教訓。 -->

KMD-120（subagent から CLAUDE.md 明示 Read を削除）では AC が「5 subagent から `Read CLAUDE.md` 行を削除」と仮説前提で書かれたが、実装段階で grep すると該当行が実在したのは 2 ファイルのみ（残り 3 は元々 no-op）と判明した。実装側は「2/5 のみ該当・残り 3 は session-context 前提の文言追加 + Constraints 補強で対応」と PR / Linear に透明開示するコメントを残す追加コストが発生し、frontmatter `description:` の整合漏れ（auto-carve KMD-156）も誘発した。

**教訓と PRD 改善**: AC で「対象ファイル群から X を削除 / 変更」のような実測前提を書く前に、`grep -rn 'pattern' <files>` で件数を確認し、AC に件数または「該当箇所のみ」を明記する。`kobaamd_create_prd` の Workflow に「AC 中に実測前提項目があれば、PRD 確定前に grep で対象ファイル群への該当件数を確認する」ステップを追加することで、本パターンを再発防止できる。

加えて、KMD-120 PRD には観測前提 AC（「次回 postmortem で input token 削減を観測」）が含まれていたが観測手段（launchd ログから input token を集計するスクリプト）が未整備で、本 postmortem 時点でも定量検証できていない。**観測前提の AC を含む PRD は、観測手段の整備を同 PR の影響範囲または別チケットとして明記する** という規約を追加する。詳細は [[postmortem-patterns]] パターン 15 / 17 と [[subagent-prompt-design]] を参照。

## Related

- [[autonomous-pipeline-philosophy]] — パイプライン全体の思想
- [[postmortem-patterns]] — 具体的な再発防止パターン（クリーン APPROVE 直行 4 条件、AC は観測 → 文言の順、観測前提 AC の観測手段セット起票を含む）
- [[wiki-reference-policy]] — wiki 参照を含む PRD/設計知見の運用標準
- [[dependency-inversion-guard]] — section 8 で書く依存逆順ガードのテンプレート
- [[subagent-prompt-design]] — KMD-120 で AC「観測 → 文言」原則を実証した subagent プロンプト設計

## Sources

- docs/learnings/2026-04-28-KMD-4.md
- docs/learnings/2026-04-28-KMD-6.md
- docs/learnings/2026-04-29-KMD-20.md
- docs/learnings/2026-05-05-KMD-54.md
- docs/learnings/2026-05-08-KMD-120.md
