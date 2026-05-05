---
description: Linear (KMD team) の todo にある指定 issue を Codex CLI で実装、ブランチ・コミット・PR まで作成して in-review に進める
---

`kobaamd_implement_code` subagent（**Opus**）を起動して、引数で指定された issue を実装してください。
Agent tool で起動する際は `subagent_type: "kobaamd_implement_code"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX`
- 引数が空の場合は、todo にある issue 一覧を提示して終了

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（Linear I/O は `./scripts/linear/lq.sh` 経由）
- `~/.zshrc` で OPENAI_API_KEY が設定済み（Codex CLI 用）
- 対象 issue が現在 todo ステータスにあること
- `docs/prd/<KMD-XX>-*.md` が存在すること（なければ PRD-lite で進む旨を案内）

完了後の報告:
- 作成した branch / PR URL
- ビルド・テスト結果
- 残課題があれば明記
