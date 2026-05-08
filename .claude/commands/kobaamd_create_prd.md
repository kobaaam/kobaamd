---
description: Linear (KMD team) の draft にある指定 issue を PRD 化して backlog に昇格させる
---

`kobaamd_create_prd` subagent（**Opus**）を起動して、引数で指定された issue を PRD 化してください。
Agent tool で起動する際は `subagent_type: "kobaamd_create_prd"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: `KMD-XX` のような issue identifier
- `--auto`: draft issue を全件自動処理する（pipeline_active から呼ばれる用途。draft がなければ "draft なし" と報告してスキップ）
- 引数が空の場合は、KMD team の draft にある issue 一覧を表示し、どれを処理するか案内するだけで終了する（無断で処理を進めない）

事前確認:
- `LINEAR_API_KEY` / `GEMINI_API_KEY` が環境にロード済みであること（`./scripts/linear/lq.sh team.get KMD` で疎通確認、Gemini は PRD 内の UI/UX リサーチで利用）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- 対象 issue が現在 draft ステータスにあること

実行手順:
1. 引数を確認
   - `KMD-XX` 指定: そのまま subagent を起動して1件処理
   - `--auto`: `./scripts/linear/lq.sh issue.list --team KMD --state draft --limit 100` で全 draft を取得し、各 issue に対して `kobaamd_create_prd` subagent を順次起動（最大5件/回。超える場合は優先度順に5件処理して残件数を報告）
   - 引数なし: draft 一覧を提示して終了
2. subagent 起動・実行
3. 完了後、subagent の最終レポートをそのまま提示

完了後の報告（subagent から受け取って提示）:
- PRD を Linear issue description に書き込んだことの確認
- Linear issue の state 遷移結果（draft → backlog）
- 埋まらなかった / TBD のセクションがあれば明記
- 次のステップ（人間が priority/label で承認するか判断）への案内

注意: PRD は docs/prd/ の MD ファイルではなく、Linear issue の description に直接書き込む。
