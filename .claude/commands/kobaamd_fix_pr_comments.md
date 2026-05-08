---
description: in-progress 状態で REQUEST_CHANGES 済みの PR に対してレビューコメントを修正し in-review に戻す。PRコメント対応ループ用
---

`kobaamd_fix_pr_comments` subagent（**Sonnet**）を起動して、PRレビュー指摘を修正します。
Agent tool で起動する際は `subagent_type: "kobaamd_fix_pr_comments"` を指定。model は agent 定義側（sonnet）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX` または PR番号 (`123`)
- `--auto`: in-progress 全件をスキャンし、REQUEST_CHANGES 済み PR があれば自動処理（pipeline_active から呼ばれる用途。対象がなければスキップ）
- 引数が空の場合: in-progress かつ REQUEST_CHANGES 済みの PR 一覧を表示して終了

事前確認:
- `LINEAR_API_KEY` / `OPENAI_API_KEY` が環境にロード済みであること（Linear I/O は `./scripts/linear/lq.sh` 経由、Codex CLI は OPENAI_API_KEY が必要）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- `gh` CLI 認証済みであること

実行手順:
1. `kobaamd_fix_pr_comments` subagent を起動
2. 引数 (`$ARGUMENTS`) を渡す
3. 完了後、subagent の最終レポートをそのまま提示

完了後の報告（subagent から受け取って提示）:
- 修正した指摘件数（fix / question / nit の内訳）
- build / test 結果
- `question` があれば人間確認が必要な内容を明示
- issue の state 遷移結果（in-progress → in-review）
