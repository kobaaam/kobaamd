---
description: in Review / Human in Review の issue に付いた人間の Linear コメントを読み取り、PRD 更新→再実装→PR 更新を一貫して行うリワークエージェント
---

`kobaamd_rework_issue` subagent（**Opus**）を起動して、人間の仕様フィードバックに基づくリワークを実施します。
Agent tool で起動する際は `subagent_type: "kobaamd_rework_issue"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`
- 引数が空の場合: in Review / Human in Review の issue 一覧を提示して終了

事前確認:
- `LINEAR_API_KEY` / `OPENAI_API_KEY` が環境にロード済みであること（Linear I/O は `./scripts/linear/lq.sh` 経由、Codex CLI は OPENAI_API_KEY が必要）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- `gh` CLI 認証済みであること
- 対象 issue が in Review または Human in Review ステータスにあること

実行手順:
1. `kobaamd_rework_issue` subagent を起動
2. 引数 (`$ARGUMENTS`) を渡す
3. 完了後、subagent の最終レポートをそのまま提示

完了後の報告（subagent から受け取って提示）:
- 反映した人間コメント件数と分類内訳
- PRD 更新の有無
- build / test 結果
- `question` があれば人間確認が必要な内容を明示
- issue の state 遷移結果
