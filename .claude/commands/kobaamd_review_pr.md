---
description: 指定 PR を kobaamd_implement_code とは別人格で批判レビューする
---

`kobaamd_review_pr` subagent（**Opus**）を起動して、引数で指定された PR をレビューしてください。
Agent tool で起動する際は `subagent_type: "kobaamd_review_pr"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `<PR番号>` または `KMD-XX`
- 引数が空の場合は、open PR 一覧を提示して終了

事前確認:
- `LINEAR_API_KEY` / `GEMINI_API_KEY` が環境にロード済みであること（Linear I/O は `./scripts/linear/lq.sh` 経由、Gemini は UI/UX 検証で利用）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- `gh` CLI 認証済み
- 対象 PR の issue が in-review ステータスにあること

完了後の報告:
- 判定: APPROVE / REQUEST_CHANGES / COMMENT
- issue state 遷移結果
- 主要指摘
