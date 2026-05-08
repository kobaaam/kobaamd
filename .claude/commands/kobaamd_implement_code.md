---
description: Linear (KMD team) の todo にある指定 issue を Codex CLI で実装、ブランチ・コミット・PR まで作成して in-review に進める
---

`kobaamd_implement_code` subagent（**Opus**）を起動して、引数で指定された issue を実装してください。
Agent tool で起動する際は `subagent_type: "kobaamd_implement_code"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`
- 引数が空の場合は、todo にある issue 一覧を提示して終了

事前確認:
- `LINEAR_API_KEY` / `OPENAI_API_KEY` が環境にロード済みであること（Linear I/O は `./scripts/linear/lq.sh` 経由、Codex CLI は OPENAI_API_KEY が必要）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- 対象 issue が現在 todo ステータスにあること
- `docs/prd/<KMD-XX>-*.md` が存在すること（なければ PRD-lite で進む旨を案内）

完了後の報告:
- 作成した branch / PR URL
- ビルド・テスト結果
- 残課題があれば明記
