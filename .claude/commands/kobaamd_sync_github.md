---
description: GitHub Issues と Linear の片方向同期。新規 GitHub Issue を Linear KMD draft に取り込む
model: sonnet
---

GitHub の kobaaam/kobaamd リポジトリの Issues を確認し、未取り込みのものを Linear KMD team の draft に起票してください。

引数: `$ARGUMENTS`
- 期待形式: なし
- オプション: `--days N` で過去N日分のみ対象（デフォルト7）

事前確認:
- `gh` CLI 認証済み
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む
- Linear の標準 GitHub 連携設定がある場合は重複起票しないよう注意（既存 issue の links を確認）

実行手順（`LQ=./scripts/linear/lq.sh`）:
1. `gh issue list --repo kobaaam/kobaamd --state open --limit 50 --json number,title,body,createdAt,labels`
2. 各 GitHub issue について、Linear に同タイトルの issue が存在しないか確認: `$LQ issue.list --team KMD --limit 250` の結果に対して `jq 'map(select(.title | contains("<title>")))'` などでローカルマッチ
3. 存在しなければ Linear KMD team の `draft` に新規起票:
   ```bash
   $LQ issue.create \
     --team KMD --state draft --priority 4 \
     --title "[GH#<num>] <original title>" \
     --body @/tmp/gh_body.md
   ```
   description はファイルに GitHub issue body + URL を書き出して `@file` で渡す
4. 既存 issue があれば、人間に通知のみ（lq.sh は links 操作未対応のためスキップ）
5. 取り込み件数を報告

外部コントリビューターからの貢献を取りこぼさないことが目的。Linear 標準の GitHub 連携が機能していればこのコマンドは原則不要だが、補助として残す。

完了後の報告:
- 取り込んだ GitHub issue 数
- スキップ（既存）数
- リンク追加した既存 issue 数
- 未取り込みの理由（あれば）
