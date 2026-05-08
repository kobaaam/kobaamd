---
description: docs/learnings/ や docs/adr/ の追加情報を読み取り、docs/wiki/articles/ を更新もしくは新規記事を生成して LLM Wiki を最新化する
---

`kobaamd_update_wiki` subagent（**Opus**）を起動して、wiki を更新してください。
Agent tool で起動する際は `subagent_type: "kobaamd_update_wiki"` を指定。

引数: `$ARGUMENTS`

| パターン | 効果 |
|---|---|
| `--source <path>` | 特定ファイルのみ取り込み（例: `--source docs/learnings/2026-05-01-KMD-27.md`） |
| `--since-last-run` | `docs/wiki/log.md` の最終 ingest 以降に変更されたソースを自動検出 |
| `--since-last-month-low` | 先月作成された learnings のうち `wiki_value: low` を救済対象として一括検討（pipeline_weekly 月初から起動。KMD-133） |
| 引数なし | 過去 7 日間に変更された `docs/learnings/*.md` と `docs/adr/*.md` 全件 |

事前確認:
- `docs/wiki/SCHEMA.md` が存在すること
- `docs/wiki/articles/` ディレクトリが存在すること
- 対象ソースが 0 件の場合は "no new sources" を報告して終了

完了後の報告:
- 処理ソース件数 / 持ち越し件数
- 更新した記事 / 新規作成した記事
- スキップしたソースとその理由
- 矛盾検出など特記事項

呼び出し元:
- 手動: 人間が任意のタイミングで起動
- 自動: `kobaamd_review_postmortem` 完了時 / `kobaamd_pipeline_weekly` 内
