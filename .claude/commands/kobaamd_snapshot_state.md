---
description: Linear KMD チームの全 issue ステータスをスナップショットとして .logs/pipeline_state.json に書き出す。pipeline_active の前後で呼ばれる。
---

Linear KMD チームの全アクティブ issue のステータスを取得し、`.logs/pipeline_state.json` に書き出してください。

## 手順

0. `LINEAR_API_KEY` が環境にロード済みであることを前提とする。手動実行時は冒頭の Bash invocation で `source ~/.zshrc` を 1 回実行する。pipeline_active 経由で呼ばれた場合は親プロセスが既に source 済みのため不要（KMD-131）
1. `./scripts/linear/lq.sh issue.list --team KMD --limit 250` で全 issue を取得（lq.sh は includeArchived=false がデフォルト）
2. 以下の JSON 形式で `.logs/pipeline_state.json` に **上書き** 保存:

```json
{
  "timestamp": "2026-04-30T13:30:00+09:00",
  "source": "pre-run" | "post-run",
  "issues": {
    "KMD-XX": { "title": "...", "status": "...", "priority": "..." },
    ...
  },
  "summary": {
    "draft": ["KMD-XX", ...],
    "backlog": ["KMD-XX", ...],
    "todo": ["KMD-XX", ...],
    "in_progress": ["KMD-XX", ...],
    "in_review": ["KMD-XX", ...],
    "reviewed": ["KMD-XX", ...],
    "human_in_review": ["KMD-XX", ...],
    "done": ["KMD-XX", ...]
  }
}
```

3. **差分検出**: `.logs/pipeline_state_prev.json` が存在する場合、前回のスナップショットと比較し、ステータスが変わった issue を `.logs/pipeline_transitions.log` に追記:

```
2026-04-30T13:45:00+09:00 KMD-28: draft → backlog (by: pipeline_active)
2026-04-30T13:45:00+09:00 KMD-24: todo → in_review (by: pipeline_active)
```

4. 現在の `pipeline_state.json` を `pipeline_state_prev.json` にコピー（次回差分検出用）

5. 結果を簡潔に報告:
   - 全 issue 数
   - ステータス別件数
   - 前回からの変更件数と内容
