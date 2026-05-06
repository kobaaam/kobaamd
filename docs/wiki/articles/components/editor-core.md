---
title: エディタコア (NSTextViewWrapper)
category: components
tags: [editor, nstextview, syntax-highlight, find-replace]
sources: [docs/adr/0002-nstextview-appkit-wrap.md]
created: 2026-04-30
updated: 2026-05-06
---

# エディタコア (NSTextViewWrapper)

## Summary

kobaamd のテキスト編集エンジン。NSTextView を SwiftUI にラップし、シンタックスハイライト・行番号・Find/Replace・AI インライン補完を提供する。

## Content

### 構成ファイル

- `Sources/Views/Editor/NSTextViewWrapper.swift` — NSViewRepresentable 本体
- `Sources/Views/Editor/EditorView.swift` — SwiftUI ラッパー（タブ・AI パネル統合）
- `Sources/Services/HighlightService.swift` — 正規表現ベースのシンタックスハイライト

### シンタックスハイライト

現在は正規表現ベース。Markdown の見出し・強調・コードブロック・リンク等をパターンマッチで着色。Phase 4 で TreeSitter への段階的移行を計画。

### AI インライン補完

`AppViewModel.startAIInlineCompletion()` がカーソル位置のコンテキストを AI に送信し、ゴーストテキストとして補完候補を表示。Copilot ライクな体験。

## Related

- [[appkit-swiftui-bridge]] — NSViewRepresentable パターンの概念
- [[ai-service]] — AI 補完のバックエンド
- [[mvvm-observable]] — EditorView の ViewModel 構造
- [[wkwebview-strategy]] — エディタと並走するプレビュー側戦略
- [[d2-diagram-preview]] — エディタから連携する D2 プレビュー
- [[file-tree-outline-sync]] — サイドバーとエディタの位置同期

## Sources

- docs/adr/0002-nstextview-appkit-wrap.md
