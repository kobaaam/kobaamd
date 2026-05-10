---
linear: KMD-194
status: backlog
created_at: 2026-05-10
author: Claude Opus (main session)
---

# pipeline_active 起動前の preflight check で空回りトークン消費を抑制

## 1. 背景・目的

`kobaamd_pipeline_active` は launchd で 30 分間隔で起動されるが、対象 issue が一切ない状態でも `run_bundle.sh` が無条件に `claude -p "/kobaamd_pipeline_active"` を呼ぶため、**メインセッションが起動する都度 CLAUDE.md (~8k tokens) + slash command parse のトークンが消費**される。

`kobaamd_pipeline_active.md` のステップ 0b' に no-op early return ガードがあるが、これはメインセッション内部で動作するため起動コストは回避できない。

ユーザーから「何もしてないのにトークン消費が激しい」「実行対象のステータスが存在しない場合は止めて欲しい」「haiku でステータスチェックした上で」というフィードバック。

## 2. ターゲットユーザー

- launchd を有効にして 24h pipeline を回す開発者（オーナー含む）
- API usage の月額予算を意識するユーザー

## 3. 機能要件

- **必須要件**:
  - `run_bundle.sh kobaamd_pipeline_active` の前段で対象 issue 有無を判定
  - 対象 issue がゼロなら `claude -p` を起動せず exit 0（メインセッション起動コスト 0）
  - 判定結果は `.logs/pipeline_active.log` に追記して観測可能にする
  - 判定処理自体は最大数秒で完了する（重くなったら本末転倒）
- **オプション要件**:
  - 微妙判定（Human in Review に新規人間コメントがあるか等）は Haiku subagent 経由で判定

## 4. 非機能要件

- **パフォーマンス**: preflight 実行は 10 秒以内
- **コスト**: empty queue 時のトークン消費 = 0（Linear API + gh CLI のみ）
- **fail-open**: preflight 自体が失敗（Linear API 接続不可・gh 認証切れ等）した場合は **proceed**（パイプラインは止めない）

## 5. 設計

### 判定ロジック（Bash 単独で完結）

以下のいずれかが満たされれば **proceed**（pipeline_active を起動）:

1. `Reviewed` 状態の issue が 1 件以上
2. `Human in Review` 状態の issue が 1 件以上 **かつ** その中に新規人間コメントあり
3. `in Review` 状態の issue が 1 件以上 **かつ** REQUEST_CHANGES または新規人間コメントあり
4. CONFLICTING PR が 1 件以上
5. `draft` 状態の issue が 1 件以上
6. `Todo` 状態の issue が 1 件以上 **かつ** `In Progress` 状態の issue が 0 件（WIP=1 なら Todo を消化したい）

すべて満たさなければ **skip**。`.logs/pipeline_active.log` に skip 理由を追記して exit 0。

### Haiku サブエージェント（オプション・将来拡張）

「人間コメント新規判定」は Bash でも `comment.list` の timestamp 比較で実装できるが、ハイブリッド指示の解釈や微妙な判断が必要になった場合は `claude -p --agent kobaamd_preflight_check` で Haiku に委ねる経路を残す。**初版は Bash 単独で実装**し、必要が生じた時に Haiku 経路を有効化する。

### 影響範囲

| ファイル | 変更種別 | 備考 |
|---|---|---|
| `scripts/launchd/preflight_check.sh` | 追加 | preflight 判定の本体 |
| `scripts/launchd/run_bundle.sh` | 変更 | pipeline_active のみ preflight を呼ぶ分岐を追加 |
| `scripts/launchd/README.md` | 変更 | preflight 仕様の追記 |

`pipeline_daily` / `pipeline_weekly` は対象外（頻度が低くスキップ価値が小さい）。

## 6. 受け入れ条件

- [ ] Linear に対象 issue がゼロの状態で launchd 起動 → `claude -p` が呼ばれず `.logs/pipeline_active.log` に `PREFLIGHT_SKIP: ...` のみが追記される
- [ ] Linear に Reviewed issue が 1 件あれば preflight が proceed し、メインセッションが起動する
- [ ] preflight が failure（Linear API 切断等）した場合は fail-open でパイプラインは通常通り起動する
- [ ] preflight 判定が 10 秒以内に完了する（実測）

## 7. テスト戦略

- **手動確認**:
  - 全 queue empty 状態で `./scripts/launchd/run_bundle.sh kobaamd_pipeline_active` を実行 → `claude -p` が呼ばれないことを確認
  - 何か 1 件 issue を Reviewed に置いた状態で実行 → メインセッションが起動することを確認
- **dry-run**:
  - `./scripts/launchd/preflight_check.sh` 単体で `--dry-run` 実行し、判定結果のみ表示

## 8. リスク

- **fail-open のリスク**: Linear API がたまたま遅延した場合、proceed して通常コストが発生する。これは現状と同等の挙動なので degradation ではない
- **誤判定**: 「人間コメント新規あり」を Bash の timestamp 比較で判定する際、AI コメントと人間コメントの author 判定が外れると誤って skip / proceed する → 既存 `kobaamd_pipeline_active.md` のステップ 4d と同じロジック（user.email == AI account か否か）を使えば回避

## 9. 計測指標

- 30 分起動 1 回あたりのトークン消費（empty queue 時）が **0** になること
- 通常時は preflight overhead が 10 秒以内
