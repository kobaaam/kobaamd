---
title: "E1 Agent Status Monitor"
slug: e1-agent-status-monitor
type: module
updated_commit: 8d67c7c210b1bfd44a72ab19b1d07d3b691e3b62
updated_at: 2026-06-13
freshness: current
sources:
  - path: Sources/Services/E1AgentStatusMonitor.swift
    sha: a28f39ef78644471d1dcf859aa2178f1b9ebd1fd
  - path: Sources/Services/E1AgentStatus.swift
    sha: bab62357878e87043cb5d884d895c4c1dd917482
---

# E1 Agent Status Monitor

## Overview

`E1AgentStatusMonitor` は E1 ターミナルを低頻度でサンプリングし、(1) エージェント状態（viewport テキストのパース）、(2) アクティブセッションのディスク transcript 追記を **1 本のタイマー** で行う。独立した高頻度 transcript レコーダーは廃止済み。

## Flows

1. `E1TerminalPaneView.onAppear` → `attach(terminalController, sessionCoordinator)`
2. 3 s タイマー → 全セッションの `readViewportText()` → `E1AgentStatusParser`
3. 10 ティックごと → **アクティブセッションのみ** `readScreenText()` → `E1TerminalTranscriptStore.appendDelta`
4. アプリ非アクティブ → `pauseSampling()`（タイマー停止）
5. バックグラウンドセッションが `.blocked` → 設定 ON なら通知

## Key Components

- `lastViewportHashes` — viewport 変化がなければパースをスキップ
- `lastScreenSnapshots` — SCREEN 全文は保持せず末尾 32 KB メタデータのみ（[[e1-terminal-transcript-store]]）
- `isRefreshing` — 再入防止

## Invariants & Gotchas

- SCREEN 読み取りは重い。アクティブセッション + 間引きのみ。
- 別タイマーで transcript を main で高頻度ポーリングしない（[[e1-transcript-recorder-hang]]）。

## Sources

- `Sources/Services/E1AgentStatusMonitor.swift`
- `Sources/Services/E1AgentStatus.swift`