---
linear: KMD-52
status: in-progress
created_at: 2026-05-06
author: kobaamd_implement_code (Claude Opus 4.7)
---

# [KB2] /kobaamd_lint_wiki slash command の実装

## 1. 背景・目的

`docs/wiki/SCHEMA.md`（KMD-51 で「## 記載規約」を追加）の規約を機械的に検証する Lint
機構が必要。`docs/wiki/articles/` 配下を 5 観点で検証し、違反を NDJSON で出力する。

5 観点のうち 1 つ（セクション単独文脈不備）は決定的ロジックでは表現できないため、
Anthropic Haiku を Prompt Caching 付きで使う。残り 4 観点は shell + grep / date / yq /
python フォールバックのみで判定する。

## 2. ターゲットユーザーとユースケース

- **subagent / 開発者**: wiki に新規記事を追加・更新した直後に lint を走らせて規約違反を検出
- **将来の pipeline_weekly**（KMD-54 で統合予定）/ **ingest ゲート**（KMD-55）からの呼び出し元として機能

## 3. 機能要件

### 必須要件

1. `.claude/commands/kobaamd_lint_wiki.md` を新規作成、引数で対象パスを受け取れる
2. `scripts/wiki/lint.sh` を新規作成、5 観点のチェックを実装：
   1. 孤立記事（index.md / 他記事 Related からリンクされていない）— shell + grep のみ
   2. リンク切れ（`[[wikilink]]` の参照先未存在）— shell + grep のみ
   3. stale 記事（`updated` から 60 日以上、かつ `sources` 最終更新と乖離）— shell + date のみ
   4. セクション単独文脈不備 — Haiku で判定（必須）。Prompt Caching、リトライ 3 回、最終失敗は警告 + スキップ、content_hash キャッシュ
   5. frontmatter 整合違反（必須フィールド欠落、タグ命名規約違反、Related 双方向性違反）— shell + yq、yq 不在時は python フォールバック
3. NDJSON 出力（1 行 = 1 違反）。schema:
   `{"file":"...","rule":"<rule-id>","line":<int|null>,"detail":"...","model":"shell"|"haiku"}`
4. exit code: 違反あり = 1、なし = 0、内部エラー = 2
5. `--fix` オプションで自動修正可能な項目に対応：
   - タグ正規化（lowercase + ハイフン化）
   - frontmatter 必須フィールドのデフォルト値補完
6. Haiku 利用ルール厳守:
   - `cache_control: ephemeral` をログ出力で確認可能（stderr）
   - リトライ 3 回（指数バックオフ）、最終失敗は警告ログを出してそのチェックをスキップ（処理を止めない）
   - content_hash ベースで不変セクションは判定キャッシュ（`.cache/wiki-lint.json`）

### 非ゴール

- pipeline_weekly への統合（KMD-54）
- ingest ゲート（KMD-55）

## 4. 非機能要件

- 全件 lint で 30 秒以内（Haiku 抜き、初回は別）
- shell スクリプトは `set -euo pipefail` を厳守
- 追加ランタイムは Haiku チェック時のみ（curl/jq/python3 のみで動作）

## 5. UI/UX

CLI のみ。利用例:

```bash
# 全観点 lint
./scripts/wiki/lint.sh

# Haiku をスキップしたい場合
./scripts/wiki/lint.sh --no-llm

# 自動修正
./scripts/wiki/lint.sh --fix

# 単一ファイルのみ
./scripts/wiki/lint.sh docs/wiki/articles/components/ai-service.md
```

## 6. 受け入れ条件

| AC | 内容 |
|---|---|
| AC1 | `.claude/commands/kobaamd_lint_wiki.md` が存在し、`scripts/wiki/lint.sh` を呼び出す |
| AC2 | `scripts/wiki/lint.sh` が 5 観点を実装、NDJSON で出力 |
| AC3 | 違反あり時 exit=1、なし時 exit=0 |
| AC4 | `--fix` でタグ正規化と frontmatter 補完ができる |
| AC5 | Haiku 呼び出しは Prompt Caching、リトライ 3 回、失敗時警告 + スキップ |
| AC6 | content_hash キャッシュで再実行が高速化される |

## 7. リスク・トレードオフ

- yq に依存すると環境差で動かなくなる → python フォールバック実装
- Haiku のレスポンスが不安定 → 失敗時はそのセクションをスキップ（exit=2 で止めない）
- `.cache/wiki-lint.json` は git ignore（既存 `.cache/` パターン or 追記）

## 8. 影響範囲マップ

### 新規ファイル（追加）

| パス | 役割 |
|---|---|
| `.claude/commands/kobaamd_lint_wiki.md` | slash command 定義（Bash 呼び出し） |
| `scripts/wiki/lint.sh` | メイン lint スクリプト |
| `scripts/wiki/lib/section-context-check.sh` | Haiku 呼び出し部（rule 4） |
| `docs/prd/KMD-52-lint-wiki.md` | 本 PRD |

### 既存ファイル（読み取り参照のみ、変更なし）

- `docs/wiki/SCHEMA.md` — 規約の正典
- `docs/wiki/articles/**/*.md` — lint 対象（読み取り、--fix 時のみ書き換え）
- `docs/wiki/index.md` — 孤立判定用（読み取り）
- `scripts/wiki/ask.sh` / `load_all.sh` — Haiku 呼び出しの参考実装（変更しない）

### 既存ファイル（変更）

- `.gitignore` — `.cache/wiki-lint.json` を ignore に追加（必要なら）

### 変更してはいけない箇所（明示）

- `scripts/wiki/ask.sh`：本 PR では一切触らない（lint は独自に Haiku を呼ぶ）
- `scripts/wiki/load_all.sh`：触らない
- `docs/wiki/articles/**/*.md`：`--fix` を明示的に指定したときだけ書き換える
- `docs/wiki/SCHEMA.md`：規約は KMD-51 の責務、本 PR では変更しない
- 他の `.claude/commands/*.md`：触らない（pipeline_weekly 統合は KMD-54）
- `Package.swift` / Swift コード：触らない（Swift 変更なし）

## 9. テスト戦略

- ローカル動作確認: `./scripts/wiki/lint.sh` を実行し、現在の wiki に対する違反一覧を NDJSON で取得
- ルール 1〜3, 5 は決定的なので、人為的に違反 fixture を作って検出を確認
- ルール 4（Haiku）は実 API 呼び出しを 1 ファイルでドライランし、cache_read / cache_create のログを確認
- swift build / test は本 PR で変更しないので不要だが、念のため `swift build` で既存 Swift にリグレッションがないことを確認

## 10. ロールアウト

- merge 後、`./scripts/wiki/lint.sh` をオペレータが手動実行
- KMD-54 で pipeline_weekly に組み込み、KMD-55 で ingest ゲート化（後続）
