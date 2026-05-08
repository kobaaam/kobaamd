---
description: ウィークリー系パイプライン（1 週間間隔想定）— 新案件発掘・週次レポート・改善提案
---

以下を順番に実行してください。

1. `/kobaamd_research_create_ticket` ← 新機能候補を backlog に PRD-lite 起票
2. `/kobaamd_report_status 7` ← 直近 1 週間のリードタイム・AI 採用率・コスト集計を生成
3. `/kobaamd_summarize_changelog` ← 直近タグ以降の done を集約してリリースノート生成
4. `/kobaamd_improve_prompt` ← `docs/learnings/` から各 subagent のプロンプト改善案を提案（learnings 2 件未満なら自動スキップ）
5. `/kobaamd_update_wiki --since-last-run` ← 前回 ingest 以降に増えた `docs/learnings/` / `docs/adr/` を `docs/wiki/articles/` に取り込み
5b. **月初（実行日の day-of-month が 7 以下）なら追加で** `/kobaamd_update_wiki --since-last-month-low` ← 先月の `wiki_value: low` 判定 learnings を救済対象として一括検討（KMD-133）
   - 判定例:
     ```bash
     DAY=$(date +%-d)  # 1〜31 を 0 詰めなしで取得
     if [[ "$DAY" -le 7 ]]; then
       echo "月初（day=$DAY）→ low 救済ジョブを実行"
       # → /kobaamd_update_wiki --since-last-month-low を起動
     else
       echo "月初ではない（day=$DAY）→ low 救済ジョブを skip"
     fi
     ```
   - low 判定で skip された learnings は無条件に取り込むのではなく、update_wiki が「既に類似記事あり / 抽象化困難」を判断して個別に skip / 統合する
   - 救済対象 0 件なら "no low-value learnings in last month" を報告して継続
6. `/kobaamd_lint_wiki --no-llm` ← Wiki 規約違反を検出（NDJSON）。違反 1 件以上なら `scripts/wiki/lint_report.sh --epic KMD-44` にパイプして Linear epic にコメント投稿
   - 実行コマンド例（slash 内部の指示として書く）:
     ```bash
     if [[ ! -x ./scripts/wiki/lint.sh ]]; then
       echo "wiki lint: lint.sh not found, skipping (KMD-52 not merged yet)"
     else
       set +e
       ./scripts/wiki/lint.sh --no-llm > /tmp/wiki-lint.ndjson
       lint_exit=$?
       set -e
       case "$lint_exit" in
         0) echo "wiki lint: clean" ;;
         1)
           echo "wiki lint: violations found, posting Linear comment..."
           cat /tmp/wiki-lint.ndjson | ./scripts/wiki/lint_report.sh --epic KMD-44 || true
           ;;
         2) echo "wiki lint: internal error (skipping comment)" ;;
         *) echo "wiki lint: unexpected exit=$lint_exit" ;;
       esac
     fi
     ```
   - 自動修正は行わない（人間判断を残す）。違反は KMD-44 のコメントから個別チケット起票で対応する

各ステップの結果サマリと、人間がレビュー推奨な提案があれば最後に 1 段落でまとめてください。

事前確認:
- **各 Bash invocation の冒頭で `source ~/.zshrc` を 1 回実行する**（`LINEAR_API_KEY` などをロード）。Claude Code の Bash tool は invocation ごとに独立した subshell のため、各 Bash call の先頭で毎回 source する（KMD-131）
- `ANTHROPIC_API_KEY` は step 6 では不要（`--no-llm` のため。他の step では必要）
- `gh` CLI 認証済み
