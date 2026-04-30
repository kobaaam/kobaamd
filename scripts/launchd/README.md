# scripts/launchd/

kobaamd 自律パイプラインの定期実行を macOS launchd で動かすための設定一式。

## 構成

| ファイル | 頻度 | 中身 |
|---|---|---|
| `com.kobaamd.pipeline_active.plist` | 30 分間隔 | merge_pr → assign_work |
| `com.kobaamd.pipeline_daily.plist` | 毎日 8:00 | archive_done / detect_stale / sync_github |
| `com.kobaamd.pipeline_weekly.plist` | 毎週月曜 9:00 | research / report / changelog / improve_prompt |

plist は `run_bundle.sh` 経由で `claude -p` を起動する設計。完了時に macOS 通知センターに結果を通知する。

plist 内のパスは `__KOBAAMD_DIR__` プレースホルダで書かれており、`install.sh` が実行時に絶対パスへ置換する（OSS 公開可）。

## 通知

各バンドルの完了時に、macOS 通知センターに以下が表示される。

- タイトル: `✓ kobaamd active 完了` / `✗ kobaamd weekly 失敗 (exit 1)`
- サブタイトル: 経過秒数
- 本文: ログ末尾 3 行（処理結果サマリ）

通知挙動は環境変数で制御可能（plist の `EnvironmentVariables` で設定）:

| 変数 | 値 | 効果 |
|---|---|---|
| `KOBAAMD_NOTIFY_LEVEL` | `all` (default) | 成功・失敗とも通知 |
| | `error` | 失敗時のみ通知 |
| | `none` | 通知なし |
| `KOBAAMD_NOTIFY_SOUND` | `""` (default) | 無音 |
| | `"Glass"` `"Ping"` 等 | macOS システムサウンド名 |
| `KOBAAMD_SLACK_WEBHOOK_URL` | URL | 設定すると Slack にも投稿 |

挙動を変えたいときは plist を編集して `./install.sh` で再ロード。

通知が出ない場合:
- 「システム設定 → 通知」で `Script Editor` または `osascript` の通知を許可
- 集中モード（Focus Mode）で抑制されていないか確認

## インストール

```bash
cd ~/atelier/kobaamd
./scripts/launchd/install.sh
```

冪等。既にロード済みでも一旦 unload してから再ロードする。

## 確認

```bash
launchctl list | grep kobaamd
# 期待: 3行表示される
```

## 即時手動実行（タイマーを待たずに動作確認）

```bash
launchctl start com.kobaamd.pipeline_active
```

## ログ確認

```bash
tail -f ~/atelier/kobaamd/.logs/pipeline_active.log
tail -f ~/atelier/kobaamd/.logs/pipeline_daily.log
tail -f ~/atelier/kobaamd/.logs/pipeline_weekly.log
```

## 一時停止（個別）

```bash
launchctl unload ~/Library/LaunchAgents/com.kobaamd.pipeline_active.plist
```

## 完全撤去

```bash
./scripts/launchd/uninstall.sh
```

## トラブルシューティング

**ログに何も書かれない / "claude: command not found"**

`source ~/.zshrc` で PATH が通っていない可能性。以下を確認:

```bash
which claude
# /opt/homebrew/bin/claude のような絶対パスが返ること
```

返らない場合、`~/.zshrc` で `claude` のインストール先を PATH に追加するか、plist 内の `claude` を絶対パスに書き換える。

**LLM コストが想定以上**

- pipeline_active の `StartInterval` を 1800 → 3600 に伸ばす（30分→1時間）
- 該当 plist を編集後、`./scripts/launchd/install.sh` を再実行

**スリープ復帰時に動かない**

`StartInterval` は最後の起動時刻からの経過秒なので、長時間スリープすると遅延する。
重要なジョブは `StartCalendarInterval` （時刻指定）に変更する。daily / weekly は既に時刻指定済み。

**特定ジョブを一時的に止めたい**

```bash
launchctl unload ~/Library/LaunchAgents/com.kobaamd.pipeline_active.plist
# 復活させるとき:
launchctl load ~/Library/LaunchAgents/com.kobaamd.pipeline_active.plist
```

## 設計メモ

- plist は OSS 公開を考慮して、ホームディレクトリの絶対パスをコミットしない設計（`__KOBAAMD_DIR__` プレースホルダ）
- 実行ログは `kobaamd/.logs/` に集約。`.gitignore` に追加済み
- 各バンドルは `run_bundle.sh` 経由で起動し、claude -p の結果と経過時間を集計、通知センターに結果を出す
- pipeline_active は `StartInterval` で起動時の即時キャッチアップを期待しない（`RunAtLoad: false`）。手動実行は `launchctl start`
- pipeline_daily / weekly は時刻指定なので、PC 起動状態が必須。常時起動でない場合は cron や Cloud Run など別経路を検討
- Slack 通知は `KOBAAMD_SLACK_WEBHOOK_URL` 環境変数を plist の EnvironmentVariables に追加することで有効化（コミットしないこと）
