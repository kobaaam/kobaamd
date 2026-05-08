---
description: done になった issue の振り返りを実施し docs/learnings/ に書き出す
---

`kobaamd_review_postmortem` subagent（**Opus**）を起動して、振り返りを実施してください。
Agent tool で起動する際は `subagent_type: "kobaamd_review_postmortem"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`（特定 issue を指定）または空（直近 done 1件を自動選定）

事前確認:
- `LINEAR_API_KEY` が環境にロード済みであること（Linear I/O は `./scripts/linear/lq.sh` 経由）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- `gh` CLI 認証済み
- 対象 issue が done ステータスにあること

完了後の報告:
- 出力先 learnings ファイルパス
- 主要な学び（最大3つ）
- 提案アクション数
