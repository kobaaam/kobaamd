---
linear: KMD-52
status: in-review (rework cycle 2 - human B案 reflected)
created_at: 2026-05-06
updated_at: 2026-05-06
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
   2. リンク切れ（`[[wikilink]]` の参照先未存在）— shell + grep のみ。**B 案（KMD-52 rework cycle 2 にて確定）**: 解決は `slug 一致 OR frontmatter.title 一致` の両形式を許容（後述 §11 参照）
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
| AC7 | broken-link 解決は slug 一致 OR frontmatter.title 一致の両形式を許容（B 案） |
| AC8 | `docs/wiki/SCHEMA.md` に wikilink 解決ルールが明文化されている（B 案：両形式許容、推奨は slug） |

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
- `docs/wiki/SCHEMA.md` — wikilink 解決ルールを記載する新セクションを追加（B 案 / rework cycle 2 にて追加。既存の §1〜§5 は触らない）

### 変更してはいけない箇所（明示）

- `scripts/wiki/ask.sh`：本 PR では一切触らない（lint は独自に Haiku を呼ぶ）
- `scripts/wiki/load_all.sh`：触らない
- `docs/wiki/articles/**/*.md`：`--fix` を明示的に指定したときだけ書き換える
- `docs/wiki/SCHEMA.md` の既存セクション（記事フォーマット、記載規約 1〜5、ワークフロー、パイプライン統合）：本 PR では**追記のみ**。既存規約の改変はしない
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

## 11. wikilink 解決ルール（B 案決定 / rework cycle 2）

### 背景

cycle 1 のレビューで、`scripts/wiki/lint.sh` の broken-link 検出ロジックが日本語タイトル形 wikilink（例: `[[エディタコア (NSTextViewWrapper)]]`、`[[AppKit-SwiftUI ブリッジ]]`、`[[MVVM と Observable パターン]]`、`[[ポストモーテムから学ぶ実装パターン]]` 等）をすべて broken-link 判定する問題が human-judgment として残された。`docs/wiki/SCHEMA.md` の wikilink 構文に slug 限定 / title alias 許容のどちらかが明記されていなかったため、3 案（A: slug-only、B: title alias 許容、C: 両形式許容 + 明文化）が提示された。

### 決定（人間判断 / 2026-05-05T23:25 by es57ster@gmail.com）

**B 案を採用**: title alias を許容する。broken-link 検出は「slug 一致 OR `frontmatter.title` 一致」の両形式を許容するロジックに拡張する。既存資産（日本語タイトル wikilink 計 6 件 / 4 記事）を温存する。

### 仕様（lint.sh 実装）

`slug_lookup` ヘルパーを以下のロジックに拡張する。

1. `[[wikilink]]` の inner text を `name` とする
2. **slug 一致（優先）**: `articles/**/<name>.md` のファイルが存在すれば、その相対パスを返す
3. **title 一致（フォールバック）**: 全 articles をスキャンし、`frontmatter.title` が `name` と完全一致する記事があれば、その相対パスを返す
4. どちらにも一致しない場合のみ broken-link として `emit`

両形式に同時に一致するケース（slug = "foo"、別記事が `title: foo`）は slug 優先とする。title 一致は線形スキャンになるため、起動時に `articles/**` を 1 度だけ走査して `title → relpath` の連想配列をビルドし、ルックアップは O(1) にする（既存の `slug_index_tmp` と並列の `title_index_tmp` を持つ）。

### 仕様（SCHEMA.md 明文化）

`docs/wiki/SCHEMA.md` の「記載規約」末尾に新セクション「### 6. wikilink の解決ルール」を追加し、以下を明記する。

1. wikilink `[[name]]` は **slug 一致を最優先**、見つからなければ `frontmatter.title` 完全一致でフォールバック解決する
2. 新規記事を生成・更新する subagent（`kobaamd_update_wiki` 等）は **slug 形式（lowercase-kebab）を必ず使用**する。title alias 形式での新規生成は禁止
3. 既存の日本語タイトル形 wikilink は移行コストの観点で温存する（B 案の意図）。lint は両形式を broken-link 判定しない
4. 同一 name に対して slug 一致と title 一致が両方成立する場合は slug 優先

### 影響範囲

- `scripts/wiki/lint.sh`: `slug_lookup` 拡張、`title_index_tmp` 追加（30〜50 行程度）
- `docs/wiki/SCHEMA.md`: 新セクション「### 6. wikilink の解決ルール」追加（30 行程度）
- 動作検証: `./scripts/wiki/lint.sh --no-llm` 実行で broken-link が 7 件 → 1 件（`[[PRD 品質サイクル]]` のみ。これは記事自体が未作成のため真の broken-link）に減ることを確認

### A 案・C 案を選ばなかった理由（記録）

- A 案（slug-only 強制）: 既存の日本語タイトル wikilink 6 件を slug 形式に書き換える別 PR が必要。本サイクルのスコープが広がる
- C 案（両形式許容するが新規も両形式 OK）: SCHEMA としての一貫性が下がる。生成側を slug に統一しないと将来的に title 揺れによる broken-link が増える
