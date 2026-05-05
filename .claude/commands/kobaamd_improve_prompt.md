---
description: docs/learnings/ から kobaamd_* subagent のプロンプト改善案を生成する
---

`kobaamd_improve_prompt` subagent（**Opus**）を起動して、プロンプト改善提案を生成してください。
Agent tool で起動する際は `subagent_type: "kobaamd_improve_prompt"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: 特定 subagent 名（例: `kobaamd_create_prd`）または空（全エージェント横断）

事前確認:
- `docs/learnings/` に少なくとも2ファイル以上のポストモーテムがあること
- なければ「データ不足」として中止

完了後の報告:
- 出力先 prompt-suggestions ファイルパス
- レビュー対象 subagent 数
- 生成提案数
- 特に重要な提案
