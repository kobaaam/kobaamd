---
description: 指定 PR / branch で swift build / swift test を実行し、結果を Linear に記録する
---

`kobaamd_validate_build` subagent（**Sonnet**）を起動して、引数で指定されたものをビルド・テスト検証してください。
Agent tool で起動する際は `subagent_type: "kobaamd_validate_build"` を指定。model は agent 定義側（sonnet）に従う。

引数: `$ARGUMENTS`
- 期待形式: `<PR番号>` または `KMD-XX`
- 引数が空の場合は、in-review にある issue / PR 一覧を提示して終了

事前確認:
- swift / xcode-select コマンドが使えること
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（Linear I/O は `./scripts/linear/lq.sh` 経由）

完了後の報告:
- build / test の pass/fail
- 失敗時は根本原因仮説
- Linear コメント投稿の有無
