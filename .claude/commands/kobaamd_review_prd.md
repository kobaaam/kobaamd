---
description: 指定 KMD-XX の PRD を kobaamd_create_prd とは別人格で品質レビューする
---

`kobaamd_review_prd` subagent（**Opus**）を起動して、引数で指定された issue の PRD を品質レビューしてください。
Agent tool で起動する際は `subagent_type: "kobaamd_review_prd"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`
- 引数が空の場合は、KMD team の backlog issue 一覧を提示して終了

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（Linear I/O は `./scripts/linear/lq.sh` 経由）
- 対象 KMD-XX の Linear issue description に PRD が書き込まれていること

完了後の報告:
- 判定: PASS / REQUEST_REVISION
- セクション別 pass/concern/fail のサマリ
- 主要指摘

注意: PRD は docs/prd/ のファイルではなく、Linear issue の description から読み込む。
