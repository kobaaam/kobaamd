---
description: Linear todo にあるチケットから次に着手すべき1件を選定して提案する。WIP=1 制御用
---

KMD team の `todo` ステータスにある issue の中から、次に着手すべき1件を選定して提案してください。

引数: `$ARGUMENTS`
- 期待形式: なし（引数不要）または `--auto` で自動的に `/kobaamd_implement_code` を呼ぶ
- 既に in-progress に1件以上ある場合は、新規アサインしない（WIP=1 ルール）

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（`scripts/linear/lq.sh` が必要）
- in-progress の issue 数を確認（>=1 ならアサイン中止）

選定基準（優先順位）:
1. priority が高い (1=Urgent > 2=High > 3=Normal)
2. label に `ai-research` がない（人間承認済み）
3. 依存関係（blockedBy）がすべて done
4. サイズ S を優先（小さく速く回す）
5. 同条件なら createdAt 古いもの

実行手順（`LQ=./scripts/linear/lq.sh`）:
1. `$LQ issue.list --team KMD --state Todo --limit 100` で一覧
2. `$LQ issue.list --team KMD --state "In Progress" --limit 50` で in-progress カウント取得
3. WIP 制限チェック（>=1 ならアサイン中止して報告）
4. 上記基準でソート、トップ1件を選定
5. 選定理由を提示
6. `--auto` 引数があれば `/kobaamd_implement_code <KMD-XX>` を呼ぶ

完了後の報告:
- 選定された issue: KMD-XX (title)
- 選定理由（priority / size / age など）
- WIP状態（in-progress: N件）
- 次のアクション（手動 or 自動）
