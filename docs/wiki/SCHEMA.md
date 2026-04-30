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
1. index.md から関連記事を検索
2. 記事を読み込んで合成回答
3. 有用な分析は新規記事として wiki に追加

### Lint（メンテナンス）
1. 矛盾する記述の検出
2. 孤立記事（どこからもリンクされていない）の特定
3. 古くなった情報のフラグ付け

## パイプライン統合

- `pipeline_weekly` に wiki ingest ステップを追加予定
- `review_postmortem` 完了時に自動で wiki を更新
- ADR 作成時に自動で decisions/ に記事を生成
