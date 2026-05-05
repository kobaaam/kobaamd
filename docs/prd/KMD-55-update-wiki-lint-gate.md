---
linear: KMD-55
status: in-progress
created_at: 2026-05-06
author: kobaamd_implement_code (Claude Opus 4.7)
---

# [KB2] kobaamd_update_wiki に ingest 時 lint ゲートを追加

## 1. 背景・目的

`/kobaamd_update_wiki` は postmortem や ADR を Wiki に取り込む subagent。
KMD-52 で `/kobaamd_lint_wiki` が整備されたので、ingest 直後（commit 直前）に
lint をかけて、規約違反のまま wiki を汚染することを防ぐ。

「fail-fast」運用にすることで、後続 ingest の前に問題を検出 → 自動修正 or
人間判断ルートに乗せる。

## 2. ターゲットユーザーとユースケース

- **`kobaamd_review_postmortem` 経由の自動 ingest**: postmortem → wiki 同期で
  違反入りの記事をマージしてしまうのを防ぐ
- **`pipeline_weekly` 経由の `--since-last-run` ingest**: 週次で蓄積した
  ソースを取り込むときの品質ゲート
- **手動の `--source` ingest**: 開発者が手動で 1 件取り込むときも同じゲート

## 3. 機能要件

### 必須要件

1. `.claude/agents/kobaamd_update_wiki.md` の Workflow に lint ゲート step を
   追加する。挿入位置は **step 5（log.md 追記）と step 6（Final Report）の
   間**。理由: index.md / log.md 更新まで終えた状態（つまり commit すれば
   ingest が完成する状態）で lint を回し、合格してからユーザーに完了報告を
   出す流れにしたい。

2. lint ゲートのフロー:
   1. `./scripts/wiki/lint.sh --no-llm` を実行
      - 理由: ingest 直後は wiki 全体ではなく今回触った記事の整合性確認が
        主目的。Haiku ベースの section-context-missing は時間がかかるので
        無人 ingest では `--no-llm` で 4 観点（orphan / broken-link / stale /
        frontmatter）にとどめる。手動 ingest では呼び出し側が
        `WIKI_LINT_LLM=1` env を設定すれば `--no-llm` を外して実行する
   2. 終了コード判定:
      - `0` (違反なし): そのまま step 6 の Final Report に進む
      - `1` (違反あり): 下記「3. 違反検出時のリカバリ」へ
      - `2` (内部エラー): warning を Final Report の「特記事項」に明記し、
        commit は行うが「lint 未完」フラグを立てる（後続の手動確認に委ねる）
   3. `lint.sh` 不在時は warning を stderr に出して step 6 に進む（KMD-52
      未マージ環境での保険）

3. 違反検出時のリカバリ（自動修正 → 再 lint → commit / 報告）:
   1. 違反 NDJSON を一時ファイルに保存（`.logs/wiki_lint_ingest_<timestamp>.ndjson`）
   2. **自動修正可能な違反のみ**を `lint.sh --fix` で対処:
      - 対象: lint.sh が `--fix` で対応する範囲のみ（タグ正規化 /
        必須フィールド欠落の TODO 補完 / frontmatter ブロック挿入）
      - これら以外の違反（broken-link / orphan / stale / section-context）は
        自動修正不可。`--fix` を呼んでも修正されない
   3. `--fix` 実行後、再度 `lint.sh --no-llm` を実行
   4. 再 lint で違反 0 件: そのまま step 6 へ進み、commit する
      （`--fix` の差分も含めて）
   5. 再 lint でも違反が残る: **commit せず**に Linear へ報告する:
      - 報告先 issue:
        - トリガーが `kobaamd_review_postmortem` 経由なら、対応する postmortem
          の Linear issue（呼び出し時に `--linear-issue KMD-XX` 引数 or
          `KOBAAMD_LINEAR_ISSUE` env で渡される想定。未指定時は epic KMD-44）
        - `--since-last-run` 経由なら epic KMD-44（[KB] kobaamd ナレッジベース整備）
        - 手動 `--source` なら呼び出し側が `--linear-issue` を指定。未指定時は
          stderr に警告して Linear 投稿は省略
      - 報告内容: 違反ルール別の集計 + 上位 5 件の詳細（ファイル / rule /
        line / detail）。NDJSON 全文は `.logs/wiki_lint_ingest_*.ndjson` を
        参照する旨を併記
      - 投稿は `./scripts/linear/lq.sh comment.add <issue-id>` で実施
   6. Working tree のロールバック方針:
      - 自動修正で `--fix` が当たった分は **戻さない**（git diff に残す）。
        理由: `--fix` の差分は lint 観点で正しい修正であり、人間が後続で
        commit するか確認するときの判断材料になる
      - `step 3〜5`（記事更新・新規作成・index.md / log.md 更新）の差分も
        戻さない（同上）
      - `commit` だけを行わない。最終報告で「commit 未実施 / 違反 N 件残り」を
        Final Report に明記する

4. Final Report の更新:
   - 既存フォーマットの末尾「特記事項」に lint 結果を必ず含める:
     - `lint: pass` / `lint: pass-after-fix(--fix で N 件自動修正)` /
       `lint: fail(N 件残り、commit 中止、Linear 報告済み: KMD-XX)` /
       `lint: error(内部エラー、commit は実施)` / `lint: skipped(lint.sh 不在)`

5. 既存 Workflow ステップ（1〜5）の挙動は変えない。lint ゲートは「step 5 と
   step 6 の間」に純粋な追加 step として挿入される。

### オプション要件（本 PR では実装しない）

- 違反詳細を GitHub Issue として起票（Linear コメントで十分）
- ルール別の閾値（v1 では 1 件以上で必ず通知）
- 自動修正不可な違反（broken-link / orphan / stale）の自動修復ヒューリスティック
- `WIKI_LINT_LLM=1` 環境変数による `--no-llm` 解除（仕様には書くが、運用で
  実際に使うかは KMD-54 と歩調を合わせる）

## 4. 非機能要件

- **実行時間**: `--no-llm` モードの lint は数秒〜数十秒（記事数 N に対し
  概ね線形）。ingest 全体の体感を大きく損ねない
- **冪等性**: lint ゲートは何度実行しても同じ違反を検出する。`--fix` も
  二度走らせても結果が変わらない（lint.sh 側で保証されている）
- **セキュリティ**: lint.sh は wiki ファイルしか読まない。LINEAR_API_KEY は
  既存の `lq.sh` 経由でのみ参照
- **失敗安全**: lint.sh の不在 / 内部エラーで ingest 全体を止めない
  （warning を出してそのまま完了する）

## 5. UI/UX

CLI のみ。Final Report 例:

```
## Wiki 更新完了

トリガー: --source docs/learnings/2026-05-01-KMD-27.md
処理ソース: 1 件 / 持ち越し: 0 件

更新した記事: 2
- articles/practices/security-hardening.md ← docs/learnings/2026-05-01-KMD-27.md
- ...

新規作成した記事: 0
スキップ: 0

index.md / log.md: 更新済み

特記事項:
- lint: pass-after-fix（--fix で 1 件 [tags 正規化] 自動修正、再 lint で違反 0 件）
```

違反残り時の Linear コメント例:

```markdown
## Wiki Lint Failure (2026-05-06 ingest)

`/kobaamd_update_wiki` の ingest 直後 lint で違反 3 件を検出しました。
自動修正後も残っているため、commit は中止しました。

### ルール別件数

| rule | count |
|---|---|
| broken-link | 2 |
| orphan | 1 |

### 上位 5 件

| file | rule | line | detail |
|---|---|---|---|
| docs/wiki/articles/foo.md | broken-link | 42 | wikilink target 'bar' not found |
| ... |

詳細 NDJSON: `.logs/wiki_lint_ingest_20260506-123456.ndjson`

→ 修正方針:
- 自動修正不可な違反は人間判断推奨
- working tree には ingest の差分が残っているので、修正後 commit すること
```

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] AC1: `.claude/agents/kobaamd_update_wiki.md` の Workflow に「lint ゲート」
      step が追加されており、step 5（log.md 追記）と step 6（Final Report）の
      間に位置する
- [ ] AC2: `--fix` 実行 → 再 lint で違反 0 件なら commit する流れが prompt に
      明記されている
- [ ] AC3: 再 lint でも違反が残る場合、**commit せず**に Linear へ概要コメントを
      投稿する流れが prompt に明記されている
- [ ] AC4: lint.sh 不在 / 内部エラー時のフォールバック（warning + 続行）が
      prompt に書かれている
- [ ] AC5: Final Report の特記事項に lint 結果を必ず含めるよう
      フォーマットが更新されている
- [ ] AC6: 既存 Workflow ステップ 1〜5 の挙動・順序が変わっていない
- [ ] AC7: swift build が通る（Swift コードに触らないので回帰なし）

## 7. テスト戦略

- 静的検証: `.claude/agents/kobaamd_update_wiki.md` を読み返して AC1〜AC6 を
  目視確認。Markdown lint（自前ルールなし）は省略
- swift build: Swift コードは触らないが、CI 互換性確認のため一度実行
- 統合テスト: 本 PR では実走しない。KMD-52 マージ後 + 実 ingest で検証する
  - 動作確認手順: 任意の postmortem を 1 件 ingest し、Final Report に
    `lint: pass` 等が出るか確認
- 失敗系テスト: lint.sh が不在の状態（main 未マージ時）でも update_wiki が
  warning を出して完走することを目視確認

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `.claude/agents/kobaamd_update_wiki.md` | 変更 | Workflow に lint ゲート step 追加 + Final Report フォーマット更新 |
| `docs/prd/KMD-55-update-wiki-lint-gate.md` | 追加 | 本 PRD |

### 共有コンテナへの注意

- `scripts/wiki/lint.sh`: KMD-52（PR #62）で実装中。**本 PR では呼び出すのみ**
- `scripts/wiki/ask.sh` / `load_all.sh`: 触らない
- `scripts/linear/lq.sh`: 既存ヘルパー。`comment.add` で使うのみ
- 他の `.claude/agents/*.md`: 触らない（本 PR は update_wiki のみ）
- 他の `.claude/commands/*.md`: 触らない
- `docs/wiki/SCHEMA.md`: 触らない（規約の正典）
- Swift コード（`Sources/`）: 一切触らない

### 変更してはいけない箇所（明示）

- `kobaamd_update_wiki.md` の既存 Workflow step 1〜5 の中身（順序・引数・
  既存記事の更新ルール / 新規作成ルール / index.md / log.md の規約）
- `kobaamd_update_wiki.md` の Constraints セクション（記載規約 5 項目の遵守
  ルール、ループ上限 5 ソース等）
- `scripts/wiki/lint.sh` の挙動（呼び出すのみで変更しない）
- `scripts/wiki/lib/section-context-check.sh`（同上）
- `.claude/commands/kobaamd_lint_wiki.md`（同上）
- `docs/wiki/SCHEMA.md` の記載規約
- `kobaamd_review_postmortem` / `pipeline_weekly` の呼び出し方（本 PR では
  update_wiki 内部の挙動のみ変える。caller 側の引数渡しは触らない）
- Swift コード一切

### その他リスク

- **KMD-52（PR #62）が main 未マージ**: 本 PR がマージされても、main に lint.sh
  が無いため lint ゲートは「lint.sh 不在 → warning + skip」で動く。実運用で
  ゲートが効くのは KMD-52 マージ後
- 違反過剰時の Linear コメント肥大: 上位 5 件 + 集計表で固定長に抑える
  （KMD-54 と同じ方針）
- `--linear-issue` 引数を caller 側が渡さない場合のフォールバック挙動:
  epic KMD-44 を参照。ただし手動 `--source` は警告して Linear 投稿スキップ
  （誤通知を避ける）

## 9. 計測・成果指標

- ingest ジョブログ（呼び出し元の Final Report）に `lint:` 行が必ず出る
- KMD-44 / 個別 issue のコメント数で違反検知頻度を可視化（Linear UI）

## 10. 参考資料

- `docs/prd/KMD-52-lint-wiki.md` — lint.sh の仕様
- `docs/prd/KMD-54-pipeline-weekly-lint.md` — pipeline_weekly での組み込み（v1）
- `docs/wiki/SCHEMA.md` — 規約の正典
- `.claude/agents/kobaamd_update_wiki.md` — 改修対象
- `.claude/agents/kobaamd_review_postmortem.md` — 主要呼び出し元
- `.claude/commands/kobaamd_pipeline_weekly.md` — 副次的呼び出し元
