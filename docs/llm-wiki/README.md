# LLM-Wiki

kobaamd 向けのエージェント用ナレッジベース。コードと乖離しないよう `sources` の SHA で freshness を追跡する。

## Frontmatter（必須）

```yaml
---
title: "Page Title"
slug: page-slug
type: module | flow | schema | concept | gotcha
updated_commit: <git rev-parse HEAD>
updated_at: YYYY-MM-DD
freshness: current | stale
sources:
  - path: Sources/Services/Foo.swift
    sha: <git hash-object -- path>
---
```

## カテゴリ

| ディレクトリ | type | 用途 |
|-------------|------|------|
| `modules/` | module | 単一モジュールの責務・API |
| `flows/` | flow | ユーザー操作やイベントの経路 |
| `schemas/` | schema | データ形状・永続化 |
| `concepts/` | concept | 横断方針・設計原則 |
| `gotchas/` | gotcha | 不変条件・ハマりどころ |

## Freshness

```bash
bash scripts/wiki-freshness.sh --json   # 検査
bash scripts/wiki-freshness.sh --write  # stale マーク
```

## 運用

- コード修正前: `INDEX.md` から関連ページを読む
- コード修正後: 影響ページを `update`、 `log.md` に追記
- スキル: `/llm-wiki <command>`（`~/.claude/skills/llm-wiki/SKILL.md`）