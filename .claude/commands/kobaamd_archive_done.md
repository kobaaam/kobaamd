---
description: Linear (KMD team) の done ステータスにあるチケットをアーカイブする。Linear free 250 issue 制限の対策
model: sonnet
---

KMD team の done にあるチケットを一括でアーカイブしてください。

引数: `$ARGUMENTS`
- 期待形式: 数字（日数。何日以上 done に滞留したものをアーカイブするか）
- デフォルト: 7日（引数なし時）

事前確認:
- `LINEAR_API_KEY` が環境にロード済みであること。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- `LQ=./scripts/linear/lq.sh` をエイリアスに設定

実行手順:
1. `$LQ issue.list --team KMD --state Done --limit 250` で done 一覧を取得（lq.sh は includeArchived=false がデフォルト）
2. `updatedAt` が `<日数>日` 以前のものをフィルタ
3. 各 issue を `$LQ issue.archive <KMD-XX>` でアーカイブする（Linear API の `issueArchive` mutation を呼ぶ）
4. 処理した issue 数を報告

完了後の報告:
- アーカイブ対象 issue 数
- 残存 done 数（アーカイブされなかったもの）
- 現在の非アーカイブ issue 総数（free plan の上限 250 までの余裕）
- フォールバックを実行した場合は手動アーカイブが必要な旨案内
