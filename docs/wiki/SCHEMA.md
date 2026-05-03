# LLM Wiki Schema

kobaamd の設計思考・意思決定プロセス・技術知見を蓄積する知識ベース。
Karpathy の LLM Wiki パターン（RAG 代替の知識コンパイル設計）に基づく。

## ディレクトリ構造

```
docs/wiki/
├── SCHEMA.md          ← 本ファイル（構造規則・ワークフロー定義）
├── index.md           ← 全記事カタログ（カテゴリ別、1行説明付き）
├── log.md             ← 操作履歴（追記専用、時系列）
├── raw/               ← 生ソース（不変、LLM は読むだけ）
│   ├── postmortem/    ← docs/learnings/ へのシンボリックリンク or コピー
│   ├── adr/           ← docs/adr/ へのシンボリックリンク or コピー
│   └── external/      ← 外部記事・論文のスナップショット
└── articles/          ← LLM が生成・更新する wiki 記事
    ├── architecture/  ← アーキテクチャ（WKWebView 戦略、メモリ管理等）
    ├── concepts/      ← 概念・パターン（MVVM, Observable, etc.）
    ├── decisions/     ← 意思決定の文脈と理由（ADR の統合ビュー）
    ├── components/    ← コンポーネント知識（EditorView, AIService, etc.）
    └── practices/     ← 開発プラクティス（パイプライン運用、レビュー基準等）
```

## 記事フォーマット

```markdown
---
title: 記事タイトル
category: architecture | concepts | decisions | components | practices
tags: [tag1, tag2]
sources: [raw/adr/0001.md, raw/postmortem/KMD-4.md]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# タイトル

## Summary
1-3行の要約。

## Content
本文。関連記事への [[wikilink]] を含む。

## Related
- [[関連記事1]]
- [[関連記事2]]

## Sources
- 参照した raw ソース一覧
```

## ワークフロー

### Ingest（取り込み）
1. raw/ にソースを追加（postmortem、ADR、外部記事など）
2. LLM がソースを読み、キーポイントを抽出
3. 既存記事の更新 or 新規記事の作成
4. 関連記事の [[wikilink]] を更新
5. index.md を更新
6. log.md に操作を記録

### Query（照会）

kobaamd では **wiki 全件を Anthropic Prompt Caching でプロンプトに投入する方式** を Phase 1 標準運用とする（`CLAUDE.md` の「Wiki 参照ポリシー」を参照）。検索層（embedding / BM25）は wiki 総量が 20 万トークンを超えるまで導入しない。

**標準手順（Phase 1: Prompt Caching）**:

1. `scripts/wiki/load_all.sh` で `docs/wiki/articles/**/*.md` を frontmatter 付きで連結し、1 つの static block を作る（KMD-46 で整備）
2. `scripts/wiki/ask.sh "<query>"` で wiki 全件 + クエリを Claude API に投げる（KMD-47 で整備）。文書部分には `cache_control: { type: "ephemeral" }` を付与し、5 分以内の再呼び出しで Cache Hit にする
3. 応答を取得し、必要なら有用な分析を新規記事として wiki に追加する
4. 実行ログから Cache Hit / Miss を確認し、cache miss が多い場合は呼び出し間隔の見直しを行う

**フォールバック手順（ヘルパー未整備時 / ad-hoc 用途）**:

1. `index.md` から関連記事を絞り込む
2. 関連記事を Read で読み込み、subagent プロンプトに埋め込んで合成回答する
3. この経路は **手動 ad-hoc 用**であり、subagent の自動処理では使わない（ヘルパー経由を必須とする）

**Phase 移行のトリガー**:

- wiki 総量 **15 万トークン** 超過: Phase 2（カテゴリ単位投入）へ移行検討
- wiki 総量 **20 万トークン** 超過: Phase 3（embedding ベース検索層 + 必要記事のみ投入）へ移行
- wiki 総量は `scripts/wiki/load_all.sh` の出力末尾サマリ（`# Total: ~XXkB / ~XX,XXX tokens` を stderr 出力）で観測する

### Lint（メンテナンス）
1. 矛盾する記述の検出
2. 孤立記事（どこからもリンクされていない）の特定
3. 古くなった情報のフラグ付け

## パイプライン統合

- `pipeline_weekly` に wiki ingest ステップを追加予定
- `review_postmortem` 完了時に自動で wiki を更新
- ADR 作成時に自動で decisions/ に記事を生成
