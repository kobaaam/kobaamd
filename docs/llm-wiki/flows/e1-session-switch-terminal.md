---
title: "E1 Session Switch Terminal Lifecycle"
slug: e1-session-switch-terminal
type: flow
updated_commit: 8d67c7c210b1bfd44a72ab19b1d07d3b691e3b62
updated_at: 2026-06-13
freshness: current
sources:
  - path: Sources/Views/E1/E1TerminalPaneView.swift
    sha: 40d4b7fdc3d44f08f68397c39dacf3d7d087b4ac
  - path: Sources/ViewModels/E1TerminalSessionController.swift
    sha: 6ab936baf10c5f3308ba691538feaf2ec0f63fa2
---

# E1 Session Switch Terminal Lifecycle

## Overview

ユーザーがセッション rail で別 worktree に切り替えたとき、PTY は **止めずに** 表示だけ切り替える。

## Flows

### セッション切替（通常）

1. `coordinator.activeSessionID` 変更
2. `E1TerminalPaneView.onChange` → `focusActiveTerminal()`
3. `ensureProcessStarted(for:)` — 未起動なら PTY 作成、既存なら `touch` で LRU 更新
4. 非アクティブ端末は ZStack 内で `opacity(0)` のまま **プロセス継続**
5. **`reclaimMemory` は呼ばない**

### PTY eviction（限定的）

| トリガー | 動作 |
|----------|------|
| 7 個目の PTY 確保 | `evictIfNeeded()` → 最古 LRU を `suspendSession` |
| `.e1TerminalMemoryPressure` 通知 | アクティブ以外を `reclaimMemory` |
| `E1TerminalPaneView.onDisappear` | 全 PTY `reclaimMemory(keeping: nil)` |
| セッション一覧から削除 | `suspendSessions(notIn:)` |

### 新規セッション初回

`ensureProcessStarted` → Ghostty surface 作成 → シェル起動

## Invariants & Gotchas

- 切替 = suspend ではない。利便性優先（[[e1-terminal-lightweight]]）。
- `suspendSession` は view を `removeFromSuperview` するが、ユーザーが意図しないタイミング（単なるタブ切替）では呼ばない。

## Sources

- `Sources/Views/E1/E1TerminalPaneView.swift`
- `Sources/ViewModels/E1TerminalSessionController.swift`