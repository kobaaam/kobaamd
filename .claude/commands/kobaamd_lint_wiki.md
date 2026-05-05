---
description: docs/wiki/articles を 5 観点（孤立 / リンク切れ / stale / セクション単独文脈 / frontmatter 整合）で lint。違反は NDJSON で報告
model: sonnet
---

`docs/wiki/articles/` 配下の wiki 記事を 5 観点で lint してください。

引数: `$ARGUMENTS`
- 想定形式（任意の組み合わせ）:
  - `--no-llm`: ルール 4（Haiku によるセクション単独文脈チェック）をスキップ
  - `--fix`: 自動修正可能な項目（タグ正規化・frontmatter 必須フィールド補完）を適用
  - `--cache <path>`: section-context キャッシュファイルのパス（デフォルト: `.cache/wiki-lint.json`）
  - `--model <id>`: Haiku モデル ID
  - `--retries <n>`: Haiku 呼び出しリトライ回数
  - 末尾にパスを並べると対象を限定（例: `docs/wiki/articles/components/`）

事前確認:
- `source ~/.zshrc` で `ANTHROPIC_API_KEY` を読み込む（`--no-llm` でない場合は必須）
- `docs/wiki/SCHEMA.md` の「## 記載規約」が判定基準

実行手順:
1. `./scripts/wiki/lint.sh $ARGUMENTS` を実行
2. NDJSON 出力（stdout）を集計し、違反をルール別にまとめる
3. 違反が 0 件なら exit=0、1 件以上なら exit=1
4. Haiku が失敗してスキップされたセクションがあれば stderr の警告ログを必ず報告

5 観点:
1. **orphan**: index.md / 他記事 Related からリンクされていない記事 — shell + grep のみ
2. **broken-link**: `[[wikilink]]` の参照先が存在しない — shell + grep のみ
3. **stale**: `updated` から 60 日以上 + `sources` の最終更新と乖離 — shell + date のみ
4. **section-context-missing**: H2/H3 セクションがそれ単体で文脈を成すか — Haiku 必須（Prompt Caching、リトライ 3 回、失敗時はスキップ）
5. **frontmatter**: 必須フィールド欠落 / タグ命名規約違反 / Related 双方向性違反 — shell のみ

非ゴール:
- pipeline_weekly への統合（KMD-54 で実施）
- ingest ゲート（KMD-55 で実施）

完了後の報告:
- 対象ファイル数 / 違反数（ルール別）
- スキップされたセクション数（Haiku 失敗）
- `--fix` を使った場合は修正したファイル数
- exit code
