---
description: PR のセキュリティレビュー（サプライチェーン・シークレット漏洩・安全でないコード・権限変更を検査）
---

`kobaamd_review_security` subagent（**Opus**）を起動して、指定 PR のセキュリティレビューを実行してください。
Agent tool で起動する際は `subagent_type: "kobaamd_review_security"` を指定。model は agent 定義側（opus）に従う。

引数: `$ARGUMENTS`
- 期待形式: PR 番号（例: `31`）または `KMD-XX`
- `--auto` が付いている場合: in-review の全 issue を対象に自動実行

事前確認:
- `gh` CLI 認証済み
- `LINEAR_API_KEY` が環境にロード済みであること（Linear I/O は `./scripts/linear/lq.sh` 経由）。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）

完了後の報告:
- 判定: PASS / WARNING / CRITICAL
- カテゴリ別結果サマリ
- CRITICAL があれば issue を in-progress に戻した旨
