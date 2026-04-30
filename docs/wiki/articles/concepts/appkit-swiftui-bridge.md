---
title: AppKit-SwiftUI ブリッジ
category: concepts
tags: [appkit, swiftui, nstextview, nsviewrepresentable]
sources: [docs/adr/0002-nstextview-appkit-wrap.md]
created: 2026-04-30
updated: 2026-04-30
---

# AppKit-SwiftUI ブリッジ

## Summary

kobaamd のエディタは NSTextView を NSViewRepresentable でラップ。macOS ネイティブの編集体験を確保しつつ SwiftUI のレイアウトシステムに統合する。macOS バージョン間の挙動差異が最大のリスク。

## Content

### NSViewRepresentable パターン

SwiftUI の `NSViewRepresentable` プロトコルを実装し、`makeNSView` で NSTextView を生成、`updateNSView` で SwiftUI 側の状態変更を反映する。Coordinator パターンで NSTextViewDelegate を処理。

### macOS 26 不可視バグ

macOS 26 で NSTextView が特定条件で不可視になるバグが発生。根本原因は `drawsBackground` プロパティの初期値が macOS バージョンで異なること。`drawsBackground = true` を明示的に設定することで解決。

**教訓**: AppKit コンポーネントは macOS メジャーバージョンアップ時に必ず動作検証する。

### WKWebView との共存

プレビュー側は WKWebView（Mermaid.js/D2 レンダリング用）。エディタ（NSTextView）とプレビュー（WKWebView）の 2 つの AppKit コンポーネントが共存する構成。

## Related

- [[mvvm-observable]] — ブリッジ上の MVVM パターン
- [[editor-core]] — NSTextViewWrapper の実装詳細

## Sources

- docs/adr/0002-nstextview-appkit-wrap.md
- memory: feedback_nstextview_macos26.md
