---
linear: KMD-54
status: in-progress
created_at: 2026-05-06
author: kobaamd_implement_code (Claude Opus 4.7)
---

# [KB2] pipeline_weekly に lint_wiki を組み込み

## 1. 背景・目的

`/kobaamd_pipeline_weekly` は新案件発掘・週次レポート・改善提案・Wiki 取り込みを
担当する。KMD-52 で `/kobaamd_lint_wiki` slash command が整備されたため、
「Wiki が SCHEMA.md の規約から逸脱していないか」を週次で機械的に検証し、
違反が見つかった場合は Linear の epic（KMD-44 [KB] kobaamd ナレッジベース整備）
にコメントを自動投稿して可視化する。

人間が判断する余地を残すため、自動修正までは行わない（lint 結果の通知のみ）。

## 2. ターゲットユーザーとユースケース

- **kobaamd の自律パイプライン運用者**: 毎週月曜 9:00 に走る weekly ジョブが
  Wiki の劣化を勝手に検知し、Linear に通知してくれる
- **subagent / 開発者**: コメントで上位 5 件の違反詳細を確認 → 個別チケットに
  分解する判断ができる

## 3. 機能要件

### 必須要件

1. `.claude/commands/kobaamd_pipeline_weekly.md` の最後（`update_wiki` の後）に
   `/kobaamd_lint_wiki --no-llm` 呼び出しを追加する。
   - `--no-llm` を付ける理由: weekly ジョブは無人実行なので、Haiku 失敗の
     stderr を見る人間がいない。決定的ルール 4 観点（orphan/broken-link/stale/frontmatter）だけで
     劣化検知は十分。Haiku ベースの section-context-missing は手動実行に委ねる。
2. lint 結果（NDJSON）を集計し、違反 1 件以上で Linear epic（KMD-44）に
   コメント投稿する集計スクリプトを作る:
   - パス: `scripts/wiki/lint_report.sh`
   - 入力: stdin に NDJSON（`scripts/wiki/lint.sh` の出力をそのまま流す）
   - 出力 / 副作用:
     - stdout: 集計サマリ（人間可読 markdown）
     - 違反 0 件: exit=0 で何もしない
     - 違反 1 件以上: `./scripts/linear/lq.sh comment.add <epic-id>` で
       コメント投稿し exit=0
   - コメント本文: 違反ルール別の集計表（行ごとに rule / count）と上位 5 件の
     詳細（file / rule / line / detail）
   - epic ID は `--epic <KMD-XX>` で指定（デフォルト KMD-44）
3. epic 検索ロジックの script 化（決め打ちを避ける）:
   - `scripts/wiki/lint_report.sh` 内に簡易検索フォールバックを実装。
     `--epic` が未指定または空のとき、`./scripts/linear/lq.sh issue.list --team KMD --limit 250` を
     呼び、`title` に `[KB] kobaamd ナレッジベース整備` を含む issue を 1 件抜き出して
     epic ID とする。見つからなければ `KMD-44` をフォールバックする。
4. lint.sh の不在時 / 実行失敗時のハンドリング:
   - `scripts/wiki/lint.sh` が存在しない場合は warning を stderr に出して exit=0
     （KMD-52 マージ前にマージされた場合の保険）
   - lint.sh の exit code は `1`（違反あり）が正常系。`2`（内部エラー）は
     stderr に warning を出して Linear コメントは投稿しない
5. `.claude/commands/kobaamd_pipeline_weekly.md` 内で違反検知時のコメント投稿を
   実行するよう手順を更新する（lint.sh → lint_report.sh のパイプ）。
6. launchd plist `scripts/launchd/com.kobaamd.pipeline_weekly.plist` の
   動作確認:
   - **新規 plist は作らない**。既存 plist が `/kobaamd_pipeline_weekly` を
     呼び出す構造で、本 PR では bundle 内容を更新するだけなので plist 改修は不要。
   - issue 本文では `com.kobaamd.weekly.plist` と書かれているが、実体は
     `com.kobaamd.pipeline_weekly.plist`。本 PR ではこの実体名でドキュメントする。

### オプション要件（本 PR では実装しない）

- 違反の自動修正（人間判断を残すため意図的に除外）
- ルール別の閾値設定（v1 では一律 1 件以上）
- Slack 通知（既存の run_bundle.sh の Slack 経路に乗ればよい）

## 4. 非機能要件

- **実行時間**: lint.sh + lint_report.sh のオーバーヘッドは weekly ジョブ全体に
  対し 10% 未満であること（weekly は他のステップが LLM 中心で重いので、
  この shell スクリプトは軽量）
- **冪等性**: コメント投稿は同じ違反でも毎週投稿される（重複抑止は v1 では
  しない。週次のリマインダー兼ねる）
- **セキュリティ**: `./scripts/linear/lq.sh` 経由のため `LINEAR_API_KEY` の
  扱いは既存運用と同等

## 5. UI/UX

CLI のみ。Linear コメント例（モックアップ）:

```markdown
## Wiki Lint Report (2026-05-06 weekly)

`/kobaamd_lint_wiki` で違反 7 件を検出しました。

### ルール別件数

| rule | count |
|---|---|
| broken-link | 3 |
| orphan | 2 |
| stale | 1 |
| frontmatter | 1 |

### 上位 5 件

| file | rule | line | detail |
|---|---|---|---|
| docs/wiki/articles/foo.md | broken-link | 42 | wikilink target 'bar' not found |
| ... |

詳細 NDJSON は weekly ジョブログを参照: `.logs/pipeline_weekly.log`

→ 修正は手動（個別チケット分解推奨）
```

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] AC1: `.claude/commands/kobaamd_pipeline_weekly.md` に lint_wiki 呼び出しが
      最後のステップとして追加されている（`update_wiki` の後）
- [ ] AC2: `scripts/wiki/lint_report.sh` が存在し、stdin の NDJSON を集計できる
- [ ] AC3: 違反 1 件以上で Linear epic（KMD-44）に `comment.add` でコメント投稿
      される（DRY-RUN テストで確認）
- [ ] AC4: コメントには違反ルール別の集計表と上位 5 件の詳細が含まれる
- [ ] AC5: epic 検索ロジックが script 化されており、決め打ちでない
      （`--epic` 未指定時は title 検索でフォールバック）
- [ ] AC6: `lint.sh` が存在しない / 内部エラー（exit=2）時は warning を
      出して安全に終了する（weekly 全体を落とさない）
- [ ] AC7: `scripts/launchd/com.kobaamd.pipeline_weekly.plist` の構造が
      変わっておらず、weekly bundle が正常に呼び出される

## 7. テスト戦略

- 単体: `lint_report.sh` を fixture NDJSON で実行し、コメント本文の整形を確認
- DRY-RUN: `LQ_DRY_RUN=1 echo '{...}' | ./scripts/wiki/lint_report.sh --epic KMD-44`
  でコメント投稿 payload が正しく生成されることを確認
- 統合: lint.sh が存在する場合 / 存在しない場合の両方で `lint_report.sh` が
  正常終了することを確認（lint.sh 自体は KMD-52 でテスト済み）
- swift build / test: 変更しないので不要。シェル + markdown のみ

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `.claude/commands/kobaamd_pipeline_weekly.md` | 変更 | step 6 として lint_wiki + lint_report を追加 |
| `scripts/wiki/lint_report.sh` | 追加 | NDJSON 集計 + Linear コメント投稿 |
| `docs/prd/KMD-54-pipeline-weekly-lint.md` | 追加 | 本 PRD |

### 共有コンテナへの注意

- `scripts/wiki/lint.sh`: KMD-52 で実装済み。**本 PR では一切変更しない**
- `scripts/wiki/ask.sh` / `load_all.sh`: 触らない
- `scripts/linear/lq.sh`: 既存ヘルパー。読み取り側として使うのみ
- `scripts/launchd/com.kobaamd.pipeline_weekly.plist`: 変更しない（bundle 名で間接的に呼ぶ構造）
- 他の `.claude/commands/*.md`: 触らない（`pipeline_weekly` のみ更新）
- `.claude/commands/kobaamd_pipeline_active.md` / `kobaamd_pipeline_daily.md`: 触らない
- Swift コード / Package.swift: 一切触らない

### 変更してはいけない箇所（明示）

- `scripts/wiki/lint.sh`（KMD-52 範囲、本 PR では呼び出すのみ）
- `scripts/wiki/ask.sh`（Wiki 参照ヘルパー、変更すると wiki ask 全体に影響）
- `scripts/wiki/load_all.sh`（同上）
- `scripts/launchd/com.kobaamd.pipeline_weekly.plist`（既存 launchd 設定）
- `.claude/commands/kobaamd_pipeline_weekly.md` の既存 5 ステップの順序・引数
  （末尾に追加するのみ。既存の `research_create_ticket` / `report_status` /
  `summarize_changelog` / `improve_prompt` / `update_wiki` の順序や引数を変えない）
- `.claude/commands/kobaamd_lint_wiki.md`（slash 定義は KMD-52 範囲）
- `docs/wiki/SCHEMA.md`（規約の正典）
- Linear epic ID `KMD-44` 自体（フォールバック先として参照するのみ）
- Swift コード（`Sources/`）一切

### その他リスク

- KMD-52 が main にマージされる前にマージされた場合: lint.sh 不在ガード
  （warning で skip）で安全に動く。lint_report.sh 単体は問題なく動く
- 違反過剰時にコメントが肥大化: 上位 5 件 + 集計表で固定長に抑える
- Linear API rate limit: weekly 1 回のコメント投稿のみなので影響軽微

## 9. 計測・成果指標

- weekly 実行ログ `.logs/pipeline_weekly.log` に lint ステップが追記される
- KMD-44 のコメント数で違反検知頻度を可視化（Linear UI）

## 10. 参考資料

- `docs/prd/KMD-52-lint-wiki.md` — lint.sh の仕様
- `docs/wiki/SCHEMA.md` — 規約の正典
- `.claude/commands/kobaamd_pipeline_weekly.md` — 既存 weekly bundle
- `scripts/launchd/com.kobaamd.pipeline_weekly.plist` — 起動設定
