---
title: MVVM と Observable パターン
category: concepts
tags: [architecture, swiftui, state-management]
sources: [docs/adr/0001-mvvm-observable.md, docs/learnings/2026-04-29-KMD-20.md]
created: 2026-04-30
updated: 2026-04-30
---

# MVVM と Observable パターン

## Summary

kobaamd は MVVM + `@Observable` を採用。View → ViewModel → Service の単方向依存を原則とするが、実践上 View が Service を直呼びする違反が繰り返し発生している。

## Content

### 設計原則

```
View → ViewModel → Service / Repository
  ↑        ↓
  └── @Observable binding
```

View は ViewModel のプロパティを参照し、ユーザー操作を ViewModel のメソッドに委譲する。Service への直接アクセスは ViewModel が担い、View は Service のインスタンスを知らない。

### @Observable の利点

Swift 5.9 の `@Observable` マクロは、プロパティ単位の変更検知を提供する。従来の `ObservableObject` + `@Published` がオブジェクト全体の再描画を引き起こしたのに対し、実際に変更されたプロパティのみ View を更新する。

### 繰り返される MVVM 境界違反

KMD-20（ファイルテンプレート）の postmortem で、`TemplatePickerView.onAppear` が `FileService()` を直接インスタンス化する違反が発見された。既存コード（SettingsView の ConfluenceService 直呼び）が慣習として広がっていることが原因。

**対策**: 実装プロンプトに「View から Service を直接インスタンス化しない」を明記。新規 View ファイルは特に注意。

## Related

- [[appkit-swiftui-bridge]] — NSTextView ラップでの MVVM 適用
- [[postmortem-patterns]] — MVVM 違反の再発防止パターン
- [[editor-core]] — EditorView の ViewModel 構造

## Sources

- docs/adr/0001-mvvm-observable.md
- docs/learnings/2026-04-29-KMD-20.md
