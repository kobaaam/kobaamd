---
description: ウィークリー系パイプライン（1 週間間隔想定）— 新案件発掘・週次レポート・改善提案
---

以下を順番に実行してください。

1. `/kobaamd_research_create_ticket` ← 新機能候補を backlog に PRD-lite 起票
2. `/kobaamd_report_status 7` ← 直近 1 週間のリードタイム・AI 採用率・コスト集計を生成
3. `/kobaamd_summarize_changelog` ← 直近タグ以降の done を集約してリリースノート生成
4. `/kobaamd_improve_prompt` ← `docs/learnings/` から各 subagent のプロンプト改善案を提案（learnings 2 件未満なら自動スキップ）
5. `/kobaamd_update_wiki --since-last-run` ← 前回 ingest 以降に増えた `docs/learnings/` / `docs/adr/` を `docs/wiki/articles/` に取り込み

各ステップの結果サマリと、人間がレビュー推奨な提案があれば最後に 1 段落でまとめてください。

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む
- `gh` CLI 認証済み
