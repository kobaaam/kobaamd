# scripts/launchd/

kobaamd 自律パイプラインの定期実行を macOS launchd で動かすための設定一式。

## 構成

| ファイル | 頻度 | 中身 |
|---|---|---|
| `com.kobaamd.pipeline_active.plist` | 30 分間隔 | merge_pr → assign_work |
| `com.kobaamd.pipeline_daily.plist` | 毎日 8:00 | archive_done / detect_stale / sync_github |
| `com.kobaamd.pipeline_weekly.plist` | 毎週月曜 9:00 | research / report / changelog / improve_prompt |
| `com.kobaamd.pipeline_resume.plist` | 毎週金曜 7:00 | one-shot 再開エージェント（後述「一時停止と再開」参照） |

plist は `run_bundle.sh` 経由で `scripts/codex/autopilot.sh` を起動する設計。Codex と Gemini のみを使い、Claude Code / Anthropic API は起動しない。完了時に macOS 通知センターに結果を通知する。

## Pre-flight check (KMD-194)

`pipeline_active` のみ、`run_bundle.sh` の冒頭で `preflight_check.sh` が走り、Linear に対象 issue がゼロの場合は Codex 起動を skip して exit する（メインセッショントークン消費を 0 にする）。

判定ロジック（OR、いずれかに該当すれば proceed）:

- `Reviewed` 状態の issue が 1 件以上
- `Human in Review` 状態の issue が 1 件以上
- `in Review` 状態の issue が 1 件以上
- CONFLICTING PR が 1 件以上
  - ただし `feature/learnings-KMD-XX` 形式の docs-only postmortem PR で、対応する Linear issue がすでに `Done` のものは **active work ではない** とみなし除外する
- `draft` 状態の issue が 1 件以上
- `Todo` 状態の issue が 1 件以上 かつ `In Progress` = 0 件

すべて満たさなければ `PREFLIGHT_SKIP: no actionable queue (...)` をログに残して exit。`Todo > 0` でも `In Progress = 1` のように **今この run で着手できる queue が無い** 場合は skip になる。Linear API / gh CLI 失敗時は **fail-open** で通常起動する（計測機構の不備で開発を止めない）。

`pipeline_daily` / `pipeline_weekly` は対象外。

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
cd ~/Documents/Claude/Projects/dev/kobaamd
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
tail -f ~/Documents/Claude/Projects/dev/kobaamd/.logs/pipeline_active.log
tail -f ~/Documents/Claude/Projects/dev/kobaamd/.logs/pipeline_daily.log
tail -f ~/Documents/Claude/Projects/dev/kobaamd/.logs/pipeline_weekly.log
```

## 一時停止（個別）

```bash
launchctl unload ~/Library/LaunchAgents/com.kobaamd.pipeline_active.plist
```

## 完全撤去

```bash
./scripts/launchd/uninstall.sh
```

## 一時停止と再開（しばらく止めたい場合）

plist は残したまま定期実行だけ止めたい場合は `bootout` を使う。`uninstall.sh` と違って plist ファイルは消さないので、`install.sh` 一発で復活する。

```bash
# 即停止
UID=$(id -u)
launchctl bootout "gui/$UID/com.kobaamd.pipeline_active"
launchctl bootout "gui/$UID/com.kobaamd.pipeline_daily"
launchctl bootout "gui/$UID/com.kobaamd.pipeline_weekly"

# 再開
./scripts/launchd/install.sh
```

### 自動再開（金曜 07:00）

`com.kobaamd.pipeline_resume.plist` は **毎週金曜 07:00 に install.sh を 1 回だけ実行** する one-shot LaunchAgent。実行後は自分自身を bootout して 1 回限りで終了する。

```bash
# 一時停止 + 自動再開を仕掛けたい場合
UID=$(id -u)
launchctl bootout "gui/$UID/com.kobaamd.pipeline_active"
launchctl bootout "gui/$UID/com.kobaamd.pipeline_daily"
launchctl bootout "gui/$UID/com.kobaamd.pipeline_weekly"

cp scripts/launchd/com.kobaamd.pipeline_resume.plist ~/Library/LaunchAgents/
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.kobaamd.pipeline_resume.plist
```

予約をキャンセルしたい場合:

```bash
launchctl bootout "gui/$(id -u)/com.kobaamd.pipeline_resume"
```

実行ログは `.logs/pipeline_resume.log` に追記される。

## トラブルシューティング

**ログに何も書かれない / "codex: command not found"**

対話シェル側の PATH に `codex` が入っていない可能性。以下を確認:

```bash
which codex
# /opt/homebrew/bin/codex のような絶対パスが返ること
```

返らない場合、`~/.zshrc` で `codex` のインストール先を PATH に追加する。`run_bundle.sh` は launchd の最小環境を補うため `zsh -lc` で PATH を取得する。

**LLM コストが想定以上**

- pipeline_active の `StartInterval` を 1800 → 3600 に伸ばす（30分→1時間）
- 該当 plist を編集後、`./scripts/launchd/install.sh` を再実行
- Codex usage が高いときは `run_bundle.sh` が Codex 起動前に soft guard で skip する
  - 既定 soft threshold: `KOBAAMD_USAGE_SOFT_THRESHOLD_CODEX=35` / `KOBAAMD_USAGE_SOFT_THRESHOLD_GEMINI=20` / `KOBAAMD_USAGE_SOFT_THRESHOLD_CLAUDE=80`（5時間窓）
  - `pipeline_active` は `Reviewed` / `Human in Review` の処理だけ threshold 超過時も続行し、それ以外（新規実装・review 継続・daily/weekly）は次回へ defer
  - 一時的に無効化する場合のみ `KOBAAMD_USAGE_GUARD=0`
- launchd 経由の Codex 既定モデルは、active が `gpt-5.4`、daily/weekly が `gpt-5.4-mini`
  - 必要時は `KOBAAMD_CODEX_MODEL_ACTIVE` / `KOBAAMD_CODEX_MODEL_MAINTENANCE` で上書き
- Token 使用量の振り返り:
  - `scripts/usage/report.sh --window-hours 24`
  - `scripts/usage/retro.sh --window-hours 168 --print`
  - `run_bundle.sh` は Codex CLI の `tokens used` を抽出し、`.logs/api_usage.jsonl` に bundle 単位で追記する
  - weekly pipeline は `.logs/token-retros/` の最新結果を prompt / model budget / 実行単位の改善入力として扱う

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
- 各バンドルは `run_bundle.sh` 経由で起動し、Codex autopilot の結果と経過時間を集計、通知センターに結果を出す
- pipeline_active は `StartInterval` で起動時の即時キャッチアップを期待しない（`RunAtLoad: false`）。手動実行は `launchctl start`
- pipeline_daily / weekly は時刻指定なので、PC 起動状態が必須。常時起動でない場合は cron や Cloud Run など別経路を検討
- Slack 通知は `KOBAAMD_SLACK_WEBHOOK_URL` 環境変数を plist の EnvironmentVariables に追加することで有効化（コミットしないこと）
