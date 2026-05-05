---
description: kobaamd の状態をスキャンし、新機能候補を Linear (KMD team) の backlog に PRD-lite 込みで起票する
---

`kobaamd_research_create_ticket` subagent（**Opus**）を起動して、本日付で kobaamd の新機能候補リサーチを実行してください。
Agent tool で起動する際は `subagent_type: "kobaamd_research_create_ticket"` を指定。model は agent 定義側（opus）に従う。

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（`./scripts/linear/lq.sh team.get KMD` で疎通確認）
- KMD team が見えること
- 接続できない場合は、CLAUDE.md の「自律開発パイプライン」セクションを参照して MCP 設定を確認するよう案内

完了後の報告:
- 起票した issue 一覧（identifier と title、対応する state は backlog）
- 採否判断のための補足情報（特に注目すべき提案、判断に迷った候補があれば理由）
- ラベル未作成等の注記があれば
