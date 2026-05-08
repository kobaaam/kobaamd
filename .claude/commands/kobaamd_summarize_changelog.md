---
description: done になった issue を集約してリリースノート Markdown を生成する
model: sonnet
---

指定期間内に done に到達した issue を集約し、リリースノートを Markdown で生成してください。

引数: `$ARGUMENTS`
- 期待形式: バージョン名（例: `v0.8.0`）または `--since YYYY-MM-DD`
- 引数なしなら直近のリリースタグから今日まで

事前確認:
- `LINEAR_API_KEY` が環境にロード済みであること。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- リポジトリの git tag を確認できること

実行手順:
1. 期間決定:
   - `--since` 指定: そこから今日まで
   - バージョン名: 直近1つ前のタグから今日まで（`git describe --tags`）
   - なし: 直近タグから今日まで
2. `./scripts/linear/lq.sh issue.list --team KMD --state Done --limit 250` のうち、updatedAt が期間内のもの取得（jq で `select(.updatedAt >= "<from>" and .updatedAt <= "<to>")`）
3. label でグループ化:
   - `type:feature` → ## Features
   - `type:bug` → ## Bug Fixes
   - `type:refactor` → ## Refactors
   - `ai-research` ラベル付き → 末尾に "(AI proposed)" 注記
4. 各 issue に対し1行: `- KMD-XX: <title>` 形式
5. PR URL があれば添付
6. ファイル出力: `docs/changelog/<version>.md`（dir なければ作成）
7. コンソールにも全文出力

完了後の報告:
- 期間: <from> 〜 <to>
- 集約 issue 数
- 出力先ファイル: `docs/changelog/<version>.md`
- 特記事項（AI 起票比率、平均リードタイムなど任意）
