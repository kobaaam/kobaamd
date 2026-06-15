---
title: "E1 Terminal Transcript Store"
slug: e1-terminal-transcript-store
type: module
updated_commit: 8d67c7c210b1bfd44a72ab19b1d07d3b691e3b62
updated_at: 2026-06-13
freshness: current
sources:
  - path: Sources/Services/E1TerminalTranscriptStore.swift
    sha: 9088e52d882df600b8b122558cb1a35528ce22a2
---

# E1 Terminal Transcript Store

## Overview

PTY 出力の長期保管は worktree 配下の `transcript.log` に追記する。Ghostty SCREEN のスナップショット間で **UTF-8 バイト差分** のみを書き、100 MB 超過で末尾を残してローテーションする。

## Key Components

- `E1TerminalTranscriptStore` — ファイル I/O と `trimToMaxBytes`
- `E1TerminalScreenSnapshot` — `utf8Count` + 末尾 `tailUTF8`（最大 32 KB）のみ保持
- `E1TerminalTranscriptDelta` — 追記差分。scrollback ロール時は 16 KB 以内で接続点を探索

## Flows

1. `appendDelta(previous, current)` → 変化なしならスキップ
2. 通常: 前回 `utf8Count` 以降を delta として追記
3. scrollback ロール: 末尾オーバーラップ探索 → 接続点以降を delta
4. 接続失敗: 現行 SCREEN 全文を新規ブロックとして追記
5. `write` 後 `trimToMaxBytes`（100 MB）

## Invariants & Gotchas

- メモリに SCREEN 全文を常駐させない。diff 用は snapshot の tail のみ。
- grapheme 単位の suffix diff は禁止（O(n²) でハング、[[e1-transcript-recorder-hang]]）。

## Sources

- `Sources/Services/E1TerminalTranscriptStore.swift`