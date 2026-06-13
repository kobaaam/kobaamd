---
title: "E1 Terminal Lightweight + Convenience"
slug: e1-terminal-lightweight
type: concept
updated_commit: 8d67c7c210b1bfd44a72ab19b1d07d3b691e3b62
updated_at: 2026-06-13
freshness: current
sources:
  - path: Sources/Services/E1TerminalMemoryPolicy.swift
    sha: 20eb0ac8ef9644cea6c00ea5f187374d0dd618de
  - path: Sources/ViewModels/E1TerminalSessionController.swift
    sha: 6ab936baf10c5f3308ba691538feaf2ec0f63fa2
  - path: Sources/Views/E1/E1TerminalPaneView.swift
    sha: 40d4b7fdc3d44f08f68397c39dacf3d7d087b4ac
---

# E1 Terminal Lightweight + Convenience

## Overview

E1 中央ペインの Ghostty PTY は **「とにかく軽い」** を最優先にしつつ、**利便性を損なわない**。セッション切替は日常操作なので、切替のたびにシェルや Claude Code を止めてはならない。軽量化はバックグラウンドのサンプリング間引き・RAM 予算・ディスク退避で達成し、PTY の生存はユーザー体験を守る。

## 設計原則

| 原則 | 意味 |
|------|------|
| **軽量** | main スレッドで SCREEN 全文を高頻度に保持しない。Ghostty scrollback は小さく（2 MB）、ログはディスク transcript へ。 |
| **利便性** | セッション切替では PTY を suspend しない。非アクティブ端末は非表示のままプロセス継続。 |
| **段階的 eviction** | PTY を止めるのは (1) 同時保持上限 6 超過時の LRU、(2) macOS memory pressure、(3) ペイン破棄時のみ。 |
| **transcript はアーカイブ** | ディスク上の `transcript.log` は閲覧・復元用。ライブ PTY の代替ではない。 |

## Key Components

- `E1TerminalMemoryPolicy` — 予算定数の単一ソース
- `E1TerminalSessionController` — PTY インスタンスの LRU eviction
- `E1TerminalPaneView` — 切替時は `ensureProcessStarted` のみ（`reclaimMemory` は呼ばない）
- `E1AgentStatusMonitor` — 軽量ポーリングでエージェント状態 + transcript

## Invariants & Gotchas

- **禁止**: `onChange(activeSessionID)` で `reclaimMemory` / `suspendSessions` を呼ぶこと。過去にこれで Claude Code が停止した。
- **許可**: 非アクティブ PTY は `opacity(0)` + `allowsHitTesting(false)` で隠すだけ。プロセスは生きる。
- transcript の SCREEN 読み取りはアクティブセッションのみ、約 30 秒間隔（`transcriptEveryNTicks`）。

## Recent Changes

- 2026-06-13: セッション切替時の自動 suspend を撤廃。軽量 + 利便性の両立を明示方針化。

## Sources

- [[e1-terminal-memory-policy]]
- [[e1-session-switch-terminal]]
- [[e1-transcript-recorder-hang]]