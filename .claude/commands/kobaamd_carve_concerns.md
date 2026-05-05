---
description: kobaamd_review_pr の concern コメントを別チケットとして退避する。引数として親 KMD-XX が必要
---

`kobaamd_review_pr` が APPROVE / COMMENT 判定で残した concern を、Linear の別チケット（Backlog / priority Low / 適切なラベル）として退避してください。`Human in Review` の人間判断時に「これは本 PR では対応せず、別 PR で扱う」と決めた concern を分離するための手段です。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`（親 issue ID）
- 引数なしなら halt して使い方を表示

## 事前確認

- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む
- `LQ=./scripts/linear/lq.sh` をエイリアス化
- `$LQ label.list KMD` で利用可能なラベル ID を確認（少なくとも `Bug` / `Feature` / `Improvement` が存在する想定）

## 実行手順

### 1. 親 issue のコメントから review_pr 出力を取得

```bash
$LQ comment.list KMD-XX
```

最新の `kobaamd_review_pr` 出力コメント（タイトルに `## PR レビュー結果` を含む）を特定する。複数ある場合は最新（createdAt 降順で先頭）を採用。

### 2. concern を抽出

コメント本文から以下を読み取る:
- 「観点別」マトリクス → 各観点が `pass` / `concern` / `fail` のどれか
- 「主要指摘 (concern/fail のみ)」セクション → 各 concern の詳細記述
- 「Gemini 検証」セクションがあれば、そこも参照（UI/UX 系の concern が多くここに出る）

`fail` がある場合は `kobaamd_fix_pr_comments` の対象なので **このコマンドの守備範囲外**。`fail=0 かつ concern>0` のときのみ起票対象。

### 3. concern を独立タスクとして整理

判断軸:

| 判断 | 起票するか |
|---|---|
| 機能横断・スコープ外（PRD section 8「変更してはいけない箇所」と衝突） | **起票する** |
| 親 PR の主目的と独立した UI/UX 改善 | **起票する** |
| 関連が深い複数 concern | **1 チケットにまとめて起票** |
| 親 PR 内で 1〜2 行で直せる軽微な指摘 | スキップ（人間に「親 PR 内で対応推奨」と提案） |
| 実機検証が必要な不確定な concern | **起票する**（検証もチケット内で扱う） |

### 4. 各 concern を Linear に起票

```bash
cat > /tmp/concern_<n>.md << 'EOF'
## 背景・目的

<親 issue/PR と review_pr concern の引用。なぜ別チケット化したかを明記>

## 想定ユーザーと利用シーン

<影響を受けるユースケース。1〜2 段落>

## 機能概要

<触るファイル・領域を具体的に。Sources/ パスを出す>

## スコープ仮見積もり

- S: 単一 View 微修正
- M: View + ViewModel + テスト
- L: 大規模変更

選択: <S | M | L>

## 想定リスク

<既存コードへの影響、エッジケース、既存テストへの波及>

## 参考リンク

- 親 issue: KMD-XX
- 親 PR: https://github.com/kobaaam/kobaamd/pull/<num>
- 該当 concern (review_pr 出力): <該当 concern の引用 1〜2 行>

---
generated_by: kobaamd_carve_concerns
parent: KMD-XX
EOF

$LQ issue.create \
  --team KMD \
  --state Backlog \
  --priority 4 \
  --labels "<label-id-from-label.list>" \
  --title "<concern を反映した命令形タイトル>" \
  --body @/tmp/concern_<n>.md
```

ラベル選択の指針:
- `Bug` ID: 既存挙動の不具合（クラッシュ・誤動作・パフォーマンス劣化）
- `Improvement` ID: 既存機能の磨き込み（UI/UX 改善・リファクタ・最適化）— **review_pr concern の大半はここ**
- `Feature` ID: 新機能としての扱いが妥当（PRD で言及されていない仕様追加）

priority は **必ず 4 (Low)**。AI 起票は人間承認ゲートを priority/label で守る原則（`CLAUDE.md` 参照）。

### 5. 親 issue にコメントで記録

```bash
cat > /tmp/parent_note.md << 'EOF'
## review_pr の concern を別チケット化

`kobaamd_review_pr` の concern N 件を別チケットに退避しました:
- KMD-AA: <タイトル>
- KMD-BB: <タイトル>

スキップした concern（親 PR 内で対応推奨）:
- <あれば箇条書き、なければ "なし">
EOF

$LQ comment.add KMD-XX @/tmp/parent_note.md
```

### 6. 親 issue の状態整理（必須・宣言だけで終わらせない）

carve-out 後は親 issue に残っている concern が無くなったかを **必ず確認・実行**する。文字でコメントに「次は Reviewed 遷移」と書くだけは禁止。実際の `lq.sh issue.transition` まで実行する。

判断ロジック:

| 起動コンテキスト | 親の残 concern | 親の状態遷移 | 後続アクション |
|---|---|---|---|
| `pipeline_active` フェーズ A ステップ 4（人間が「approval + carve」と回答） | carve-out 対象以外の concern が **すべて approval** （= 残 concern=0 と等価） | `$LQ issue.transition KMD-XX Reviewed` を実行 | `/kobaamd_merge_pr KMD-XX` を起動 |
| 同上で **rework** や **human-judgment** の concern が残っている | 残あり | 親はそのまま `Human in Review` 維持 | rework_issue / 人間追加コメントを待つ（merge_pr は呼ばない） |
| 人間が手動で `/kobaamd_carve_concerns KMD-XX` を起動した | 不明（人間が後で判断） | 親はそのまま | 「親の状態遷移は人間判断に委ねる」と最終レポートに明記し、終了 |

**必須**: 上記いずれの分岐でも、**実行した API call** と **実行しなかった理由（該当する場合）** を Linear コメントに残す。例:

```bash
cat > /tmp/carve_followup.md << 'EOF'
## carve-out 後の状態整理

- carve-out 起票: KMD-AA, KMD-BB
- 残 concern 分類: approval x 1（実機 QA 不要の判断）
- 親 issue 状態遷移: Human in Review → Reviewed（実行済み）
- 後続: kobaamd_merge_pr KMD-XX を起動（実行済み / 失敗時は本コメントを上書き）
EOF

$LQ comment.add KMD-XX @/tmp/carve_followup.md

# pipeline_active から呼ばれた場合のみ:
$LQ issue.transition KMD-XX Reviewed
# その後 kobaamd_merge_pr を起動（Agent ツール経由 or slash 経由）
```

### 7. 報告

最終レポートには以下を含める:

```
## concern carve-out 結果

親 issue: KMD-XX
親 PR: #<num>
review_pr 出力日時: <ISO>

抽出 concern: <総数>
起票: <件数>
- KMD-AA: <タイトル> (<ラベル>)
- KMD-BB: <タイトル> (<ラベル>)

スキップ: <件数>
- 内容と理由（親 PR 内対応推奨など）

親 issue 状態整理（実際に実行した API call）:
- transition: <実行 / スキップ + 理由>
- merge_pr 起動: <実行 / スキップ + 理由>

次のアクション:
- 起票済み issue は Backlog / priority Low。人間が priority を 3 (Normal) 以上に上げる or label `ai-research` を外すと `kobaamd_create_prd` 以降が拾う
- merge_pr が走った場合: done 後に `/kobaamd_review_postmortem KMD-XX` を起動するのが標準ワークフロー
```

## Constraints

- AI 起票は **必ず priority 4 (Low)**（人間承認ゲート維持）
- 親 issue のステータスは変更しない（このコマンドは concern 退避のみ。Human in Review のまま維持）
- `fail` が残っている場合はスキップして `kobaamd_fix_pr_comments` を案内する
- concern が 0 件の場合は「退避すべき concern なし」と報告して終了
- 副作用は `$LQ issue.create` 数件 + `$LQ comment.add` 1 件のみ
- すべての write は `.logs/linear_writes.jsonl` に自動記録される
- 同一 concern を二重起票しないよう、親 issue のコメントで「concern を別チケット化」が既に投稿されている場合は halt して人間に確認

## 使用例

```
/kobaamd_carve_concerns KMD-25
```

→ KMD-25 の最新 review_pr コメントから concern を読み取り、KMD-36 / KMD-37 のような follow-up を Backlog に起票し、親 KMD-25 にコメントで記録。
