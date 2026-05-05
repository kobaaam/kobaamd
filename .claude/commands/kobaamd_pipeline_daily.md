---
description: デイリー系パイプライン（24 時間間隔想定）— archive / stale 検出 / GitHub 同期
---

以下を順番に実行してください。各ステップ失敗時は次に進む。

1. `/kobaamd_archive_done 7` ← done になって 7 日以上経過したものをアーカイブ
2. `/kobaamd_detect_stale 7` ← 7 日以上動いていない issue を検出して通知
3. `/kobaamd_sync_github` ← GitHub の新規 issue を Linear draft に取り込み（OSS外部コントリビューター対応）
4. **Linear ↔ ログ整合性チェック（ステータス同期）**

   pipeline_active のログキャッシュ（`.logs/pipeline_active.log`）と Linear の実ステータスの乖離を検出・修正する。

   手順:
   a. `.logs/pipeline_active.log` の末尾 50 行から、パイプラインが「In Progress」「in Review」「ブロック中」と認識している issue ID（KMD-XX）を抽出する
   b. 抽出した各 issue の Linear 上の現在ステータスを `./scripts/linear/lq.sh issue.get KMD-XX` で取得する
   c. 乖離がある場合（例: ログでは In Progress だが Linear では Done）:
      - `.logs/pipeline_active.log` に `==== <日時> STATUS_SYNC: KMD-XX ログ上=In Progress → Linear実態=Done（同期済み） ====` を追記
      - **Linear 側は変更しない**（Linear が正。ログ側に正しい状態を記録するのみ）
   d. In Progress のまま PR もブランチも存在しない「幽霊 issue」を検出した場合:
      - Linear コメントで `[DAILY_SYNC] パイプラインログで In Progress 残留を検出。PR/ブランチなし。todo に戻すか確認してください` と投稿
   e. 結果サマリ: 乖離件数・修正内容・幽霊 issue の有無を報告

5. **コード品質チェック**: `swift-format lint -r Sources/` を実行し、違反があれば件数と主要カテゴリを報告（自動修正はしない、検出のみ）

各ステップの結果サマリ（処理件数・特に注目すべき stale issue など）を簡潔に報告。

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY` を読み込む（Linear I/O は `./scripts/linear/lq.sh` 経由）
- `gh` CLI 認証済み
