---
description: 全パイプラインを 1 周手動で走らせる（プレゼン・動作確認用、定期実行非推奨）
---

以下を順番に実行してください。

1. `/kobaamd_pipeline_weekly`
2. `/kobaamd_pipeline_daily`
3. `/kobaamd_pipeline_active`

最後に以下を提示してください:
- 各バンドルの処理件数サマリ（research起票数 / archive数 / merge数 / assign数 など）
- Linear KMD team の現在のステータス別件数
- パイプライン全体の一行サマリ（"順調 / 注意点あり / 詰まりあり"）

このコマンドはコスト・実行時間ともに重いので、定期実行ではなくデモ・動作確認用途のみで使用すること。
