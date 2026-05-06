---
description: パイプライン基盤の死活監視（EM 的視点）— launchd / ログ更新間隔 / Linear API / 環境変数 / API キー / ログサイズ / wiki 総量（Phase 移行トリガー）を確認し、CRITICAL 時は Linear に infra/health issue を起票
---

`pipeline_daily` の最初に呼ばれる基盤監視ステップ。**個別 subagent の縦割り視点では検出できない、システム全体としての停滞・異常を検知する**ことが目的。

## 実行手順

`source ~/.zshrc` を実行してから、以下を順に確認する。各項目は OK / WARNING / CRITICAL の 3 段階で判定する。

### 1. launchd ジョブの死活

3 ジョブそれぞれについて `launchctl print gui/$(id -u)/com.kobaamd.<job>` を確認:

- `com.kobaamd.pipeline_active`
- `com.kobaamd.pipeline_daily`
- `com.kobaamd.pipeline_weekly`

判定:
- **CRITICAL**: ジョブが launchctl list に存在しない、または `last exit code` が 0 以外
- **WARNING**: `runs` が 0 のまま 24 時間以上経過
- **OK**: `last exit code = 0` または `(never exited)` で正常スケジュール

### 2. pipeline_active.log の最終 end タイムスタンプ

`.logs/kobaamd_pipeline_active.log` の末尾から `end: /kobaamd_pipeline_active` 行を抽出し、最新タイムスタンプを取得。

判定（pipeline_active は 30 分間隔）:
- **CRITICAL**: 4 時間以上 end ログが出ていない（または start のみで end がない暴走疑い）
- **WARNING**: 2 時間以上 end ログが出ていない
- **OK**: 1 時間以内に end ログがある

### 3. Linear API 疎通

`./scripts/linear/lq.sh state.list KMD` を実行して、ステータス一覧が正常に返るか確認。

判定:
- **CRITICAL**: API エラー（401 / 403 / 5xx / タイムアウト）
- **OK**: 正常レスポンス

### 4. gh CLI 認証

`gh auth status` を実行。

判定:
- **CRITICAL**: ログイン切れ
- **OK**: ログイン中

### 5. 環境変数

以下が `~/.zshrc` で設定されているか確認（値の中身は出力せず存在のみチェック）:

- `LINEAR_API_KEY`
- `OPENAI_API_KEY`
- `GEMINI_API_KEY`
- `ANTHROPIC_API_KEY`（`scripts/wiki/ask.sh` 用）
- `KOBAAMD_SU_PUBLIC_ED_KEY`（リリース時のみ必須なので未設定は WARNING）

判定:
- **CRITICAL**: `LINEAR_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` / `ANTHROPIC_API_KEY` のいずれかが未設定
- **WARNING**: `KOBAAMD_SU_PUBLIC_ED_KEY` が未設定（リリース予定がない場合は無視可）
- **OK**: 全て設定済み

### 6. Codex CLI auth 状態

`~/.codex/auth.json` の存在と `auth_mode` を確認。

判定:
- **CRITICAL**: `auth.json` が存在しない（→ Codex CLI 経由の実装が全件ブロック）
- **WARNING**: `auth_mode: apikey` で `OPENAI_API_KEY` のクォータ警告がある
- **OK**: `auth_mode: chatgpt` で正常

### 7. ログサイズ（rotate 推奨判定）

以下のファイルサイズを確認:

- `.logs/linear_writes.jsonl`
- `.logs/kobaamd_pipeline_active.log`
- `.logs/pipeline_active.log`
- `.logs/kobaamd_pipeline_daily.log`
- `.logs/kobaamd_pipeline_weekly.log`
- `.logs/api_usage.jsonl`（KMD-128 実装後）

判定:
- **WARNING**: いずれかが 10 MB 以上（次の改善 issue 候補として記録）
- **OK**: 全て 10 MB 未満

### 8. ディスク空き容量

`df -h /` でルートボリュームの空き容量を確認。

判定:
- **CRITICAL**: 残 1 GB 未満
- **WARNING**: 残 5 GB 未満
- **OK**: 残 5 GB 以上

### 9. .build ディレクトリのサイズ

`du -sh .build` で確認。

判定:
- **WARNING**: 5 GB 以上（rebuild 推奨を記録）
- **OK**: 5 GB 未満

### 10. wiki 総量と Phase 移行トリガー

`scripts/wiki/load_all.sh` を実行（stderr に `# Total: ~XXkB / ~XX,XXX tokens` が出る）。トークン数を抽出して Phase 移行が必要かを判定。閾値の根拠は [[wiki-reference-policy]] §2:

| トークン数 | 判定 | 推奨アクション |
|---|---|---|
| < 12 万 | **OK** | Phase 1（現行） 維持 |
| 12 万 〜 15 万 | **WARNING（Phase 2 検討）** | カテゴリ単位の分割投入を検討開始 |
| 15 万 〜 18 万 | **CRITICAL（Phase 2 移行）** | カテゴリ単位の分割投入に移行（PR-C 系列で実装計画化） |
| 18 万 〜 20 万 | **CRITICAL（Phase 3 検討）** | embedding ベース検索層の準備開始 |
| > 20 万 | **CRITICAL（Phase 3 移行）** | 検索層 + 必要記事のみ投入に切り替え |

CRITICAL 時は Linear に `[infra/wiki-phase] wiki 総量 X トークン到達 — Phase 移行を検討` で issue 起票（`scripts/wiki/load_all.sh` の出力を添付）。

### 11. wiki 記事の untracked / modified 警告

`git ls-files --others --exclude-standard -- docs/wiki/articles/` と `git diff --name-only -- docs/wiki/articles/` を実行。

判定:
- **WARNING**: 未コミットの wiki 記事がある（過去 2 回の消失事故再発防止）
- **OK**: なし

WARNING の場合は `pipeline_health.log` に該当ファイル名を記録（Linear 起票はしない、ノイズ抑制）。

## 結果記録

判定結果を以下に記録する:

### a. `.logs/pipeline_health.log` に追記

```
==== <YYYY-MM-DD HH:MM:SS> health_check ====
launchd: pipeline_active=OK / pipeline_daily=OK / pipeline_weekly=OK
pipeline_active.log: OK (last end: <timestamp>, X 分前)
linear_api: OK
gh_auth: OK
env: OK (KOBAAMD_SU_PUBLIC_ED_KEY=WARNING: 未設定)
codex_auth: OK (chatgpt)
log_size: OK (max=<size>)
disk: OK (残 <size>)
.build: OK (<size>)
wiki_total: OK (~XX,XXX tokens, Phase 1)
wiki_uncommitted: OK
SUMMARY: OK / WARNING N件 / CRITICAL 0件
```

### b. CRITICAL 検出時の起票

CRITICAL が 1 件以上ある場合:

1. `./scripts/linear/lq.sh issue.create --team KMD --title "[infra/health] <検出日時> health_check で CRITICAL N 件検出" --body @/tmp/health_body.md --state Backlog --priority 2` で起票
2. body には CRITICAL 項目の詳細と推奨対応を記載
3. `infra` ラベル付与（あれば）
4. wiki Phase 関連の CRITICAL は `[infra/wiki-phase]` プレフィックスで起票

CRITICAL なしの場合は Linear 起票しない（ノイズ防止）。

### c. WARNING のみの場合

`pipeline_health.log` への記録のみ。Linear 起票はしない。週次の `report_status` で WARNING 件数の傾向を集計する。

## 出力（コンソール）

最終行に 1 行サマリ:

```
[health_check] OK / WARNING N件 / CRITICAL N件 (<timestamp>)
```

CRITICAL があった場合はそれに続けて項目別の詳細を 1 行ずつ出力。

## 事前確認

- `source ~/.zshrc` で各種 API キーを読み込む
- Linear I/O は `./scripts/linear/lq.sh` 経由

## 想定モデル

**Sonnet**（機械的な死活監視で判断余地が少ないため）
