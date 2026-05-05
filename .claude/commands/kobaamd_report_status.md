---
description: 週次ステータスレポートを生成する。リードタイム・AI採用率・LLMコスト目安を Markdown で出力
---

直近1週間（または引数で指定した日数）の自律開発パイプラインステータスをまとめてください。

引数: `$ARGUMENTS`
- 期待形式: 数字（日数。デフォルト7）

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（Linear I/O は `./scripts/linear/lq.sh` 経由）

集計項目:
1. **チケットフロー**:
   - 各ステータスの現在件数
   - 期間内に各ステータスに入った件数（draft→backlog 遷移など）
2. **リードタイム**:
   - draft → done の平均日数
   - backlog → done の平均日数
3. **AI vs 人間**:
   - 起票元: ai-research ラベル付き割合
   - 平均承認時間（backlog 滞留時間）
4. **失敗率**:
   - in-review → in-progress に戻った件数（reject率）
   - 平均レビューラウンド数
5. **LLM コスト目安** （計測手段が確立していなければ "未計測" と明記）

出力フォーマット: `docs/reports/weekly-<YYYY-WNN>.md`

実行手順:
1. Linear から各種 issue 集計
2. 集計値を計算
3. テンプレートに沿って Markdown 生成
4. ファイル出力
5. コンソールにサマリ表示

完了後の報告:
- 出力先ファイル: `docs/reports/weekly-<week>.md`
- ハイライト3行（最も改善した項目・最も悪化した項目・特記事項）
