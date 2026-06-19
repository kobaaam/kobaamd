---
title: "Workspace FSEvents Memory Storm"
slug: workspace-fsevents-memory-storm
type: gotcha
updated_commit: pending
updated_at: 2026-06-19
freshness: current
sources:
  - path: Sources/ViewModels/FileTreeViewModel.swift
    sha: a56b74dbc3c01b6b5f992b72009ab4e30e57d89b
  - path: Sources/App/AppViewModel.swift
    sha: f0b16a2d6d4b52dfc1b0355fb3c463617e8daf0a
  - path: Sources/Services/FileService.swift
    sha: afc4e0186bdf1091226f39c68f8021599aaeebd2
  - path: Sources/Services/WikiIndexService.swift
    sha: e3406b393a01359ea2536f1715c460dccc4077b1
---

# Workspace FSEvents Memory Storm

## Overview

長時間稼働中、`.kobaamd/transcript.log` 等の高頻度 FSEvents が連鎖し、ファイルツリー再構築・QuickOpen インデックス・Wiki 全文インデックス・タグスキャンが同時に走ると RAM が GB 単位で膨らむ。Spindump で 39GB footprint が観測された（2026-06-19）。

## Symptom Chain

```
FSEvents (.kobaamd/transcript.log 等)
  → FileTreeViewModel.reload()
  → workspaceFilesChanged 通知
  → syncOpenTabsFromDisk + refreshQuickOpenIndex
  → tags/todo/wiki setRoot → rebuildIndex ループ
  → SwiftUI が WorkspaceFolder.nodes の深い Equatable 比較
```

## Mitigations (v0.4.6)

| 対策 | 実装 |
|------|------|
| FSEvents debounce 400ms | `FileTreeViewModel.scheduleFilesystemReload` |
| インデックス更新 debounce 400ms | `AppViewModel.scheduleDebouncedWorkspaceRefresh` |
| `.kobaamd/` 常時除外 | `FileService.workspaceInternalDirectoryNames` |
| building 中の setRoot 無視 | `WikiIndexService.setRoot` が `.building` で return |
| 浅い Equatable | `WorkspaceFolder.nodesGeneration` で世代比較 |

## Invariants & Gotchas

- E1 ターミナルの transcript は **意図的に** `.kobaamd/transcript.log` へ追記する。除外はインデックス・ツリー走査のみ
- debounce はディスク同期（`syncOpenTabsFromDiskIfClean`）を即時、インデックス系を遅延させる
- 再起動だけでは構造修正にならない。v0.4.6 以降のビルドが必要

## Recent Changes

- **v0.4.6**: 上記 P0/P1 対策を実装

## Sources

- `Sources/ViewModels/FileTreeViewModel.swift`
- `Sources/App/AppViewModel.swift`
- `Sources/Services/FileService.swift`
- `Sources/Services/WikiIndexService.swift`