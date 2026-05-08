---
description: reviewed の issue を main にマージして done に遷移。Human in Review でマージ済みの issue も done に遷移（残留クリーンアップ）。失敗時は in-progress 戻し
---

`kobaamd_merge_pr` subagent（**Sonnet**）を起動して、マージを実行してください。
Agent tool で起動する際は `subagent_type: "kobaamd_merge_pr"` を指定。model は agent 定義側（sonnet）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`（単一 issue を手動マージ）または空（reviewed 全件を自動マージ、launchd 起動を想定）

事前確認:
- `LINEAR_API_KEY` が環境にロード済みであること（Linear I/O は `./scripts/linear/lq.sh` 経由）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- `gh` CLI 認証済み
- main ブランチに対する push 権限がある PAT / OAuth が設定済み

実行手順:
1. `kobaamd_merge_pr` subagent を起動
2. 引数があれば渡す、なければ auto モード
3. subagent の最終レポートを提示

完了後の報告:
- クリーンアップ件数（Human in Review → Done）
- 処理件数（成功 / 失敗 / スキップ）
- 失敗した issue は次に拾われるべき経路（in-progress 戻し済みなので /kobaamd_assign_work で拾える）
- merge-uncertain があれば人間確認を案内
