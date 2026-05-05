---
description: done になった issue の振り返りを実施し docs/learnings/ に書き出す
---

`kobaamd_review_postmortem` subagent（**Opus**）を起動して、振り返りを実施してください。
Agent tool で起動する際は `subagent_type: "kobaamd_review_postmortem"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`（特定 issue を指定）または空（直近 done 1件を自動選定）

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（Linear I/O は `./scripts/linear/lq.sh` 経由）
- `gh` CLI 認証済み
- 対象 issue が done ステータスにあること

完了後の報告:
- 出力先 learnings ファイルパス
- 主要な学び（最大3つ）
- 提案アクション数
