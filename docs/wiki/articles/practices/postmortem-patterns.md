---
title: ポストモーテムから学ぶ実装パターン
category: practices
tags: [postmortem, patterns, codex, testing]
sources: [docs/learnings/2026-04-28-KMD-4.md, docs/learnings/2026-04-28-KMD-6.md, docs/learnings/2026-04-29-KMD-20.md, docs/learnings/2026-04-28-KMD-22.md]
created: 2026-04-30
updated: 2026-04-30
---

# ポストモーテムから学ぶ実装パターン

## Summary

KMD-4/6/20/22 の振り返りから抽出した再発防止パターン集。実装プロンプトへの反映事項を体系化。

## Content

### パターン 1: 影響範囲マップ必須化

**問題**: PRD に「変更してはいけないファイル」が未記載 → Codex がスコープ外を変更
**対策**: PRD セクション 8 に「変更禁止ファイル一覧」を必須化
**効果**: KMD-20 でリワーク 0 回を達成

### パターン 2: View → Service 直呼び禁止

**問題**: `TemplatePickerView` が `FileService()` を直接インスタンス化（MVVM 違反）
**対策**: 実装プロンプトに「View から Service を直接呼ばず ViewModel 経由」を明記
**根拠**: 既存コードの慣習（SettingsView）が新規ファイルに伝播した

### パターン 3: onAppear の非同期化デフォルト

**問題**: `onAppear` 内のファイル I/O がメインスレッドをブロック
**対策**: ファイル I/O は必ず `Task { await ... }` パターンを使用

### パターン 4: テストは実装対象を経由

**問題**: テスト名が `ensureCustomTemplateDirectory` だが、実際は FileManager を直呼びしており FileService を一切検証していなかった
**対策**: テスト名に登場するメソッドは必ずテスト内で呼び出す

### パターン 5: ID 衝突を前提にした設計

**問題**: `DocumentTemplate.id` がファイル名のみ → ビルトインとカスタムで衝突可能
**対策**: `Identifiable.id` は名前空間プレフィックス付き（例: `"builtin:"`, `"custom:"`）

### パターン 6: concern の重大度分類

**問題**: KMD-22 で concern 6件が全て同列に並び、重要度が不明
**対策**: concern を severity (high/medium/low) で分類し、high は REQUEST_CHANGES 相当に

## Related

- [[mvvm-observable]] — パターン 2 の概念的背景
- [[prd-quality-cycle]] — パターン 1 の PRD への反映

## Sources

- docs/learnings/2026-04-28-KMD-4.md
- docs/learnings/2026-04-28-KMD-6.md
- docs/learnings/2026-04-29-KMD-20.md
- docs/learnings/2026-04-28-KMD-22.md
