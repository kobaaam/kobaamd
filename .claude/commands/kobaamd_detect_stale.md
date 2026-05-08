---
description: N日以上動いていない issue を検出して通知する。launchd で日次起動を想定
model: sonnet
---

KMD team の各ステータスを横断して、N日以上更新されていない issue を検出してください。

引数: `$ARGUMENTS`
- 期待形式: 数字（閾値日数。デフォルト 7）
- 例: `/kobaamd_detect_stale 14` で14日以上停滞中を検出
- 注: 人間が滞留している `Human in Review` には **時間単位の追加警告**（デフォルト 24h）を別途適用する

事前確認:
- `LINEAR_API_KEY` が環境にロード済みであること。手動実行時は冒頭で `source ~/.zshrc` を 1 回実行すれば足りる。subagent / pipeline 経由で呼ばれる場合は親プロセスが既に source 済みであることが前提（KMD-131）
- `LQ=./scripts/linear/lq.sh`

実行手順:
1. `$LQ issue.list --team KMD --limit 250` で全アクティブ issue を取得し、`updatedAt` が現在日時から N 日以上古いものを jq でフィルタ（`jq --arg cut "$(date -u -v-${N}d +%Y-%m-%dT%H:%M:%SZ)" '[.[] | select(.updatedAt < $cut)]'`）
2. ステータスごとにグループ化（draft / Backlog / Todo / In Progress / in Review / Human in Review / Reviewed）
3. Done と Canceled は除外
4. 各 issue の updatedAt と現在状態を表形式で出力
5. **`Human in Review` 用の時間単位早期警告**: `Human in Review` ステータスの全 issue について、最新の人間コメント時刻と現在時刻の差を確認する
   - **24 時間以上経過**: WARN 級として別出力。「人間判断待ち（または承認回答済みなのに AI が transition を忘れている）可能性」
   - 各 issue について最新の AI コメントと最新の人間コメントの順序を確認:
     - 最新コメントが人間で、その後 AI が反応していない → AI 側の処理漏れ疑い → 「`/kobaamd_pipeline_active` 手動キックを推奨」
     - 最新コメントが AI で、人間応答待ち → 「人間レビュー待ち」
6. ステータスごとの推奨アクション:
   - Todo で停滞: priority/label 見直し or Backlog に戻す
   - In Progress で停滞: kobaamd_implement_code が詰まっている可能性、人間介入
   - in Review で停滞: kobaamd_review_pr / Human in Review が滞っている
   - Human in Review で停滞（24h+）: 上記ステップ 5 の判定に従う

完了後の報告:
- 閾値（日次）: N日 / 閾値（時間）: 24h（Human in Review 専用）
- 検出件数: <count>（うち Human in Review > 24h: <subcount>）
- ステータス別内訳
- 特に注意すべき issue（in-progress / in-review で長期停滞、Human in Review で AI 処理漏れ疑い）
- 推奨アクション
