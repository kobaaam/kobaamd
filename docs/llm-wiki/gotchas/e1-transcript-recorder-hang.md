---
title: "E1 Transcript Recorder Hang"
slug: e1-transcript-recorder-hang
type: gotcha
updated_commit: 8d67c7c210b1bfd44a72ab19b1d07d3b691e3b62
updated_at: 2026-06-13
freshness: current
sources:
  - path: Sources/Services/E1TerminalTranscriptStore.swift
    sha: 9088e52d882df600b8b122558cb1a35528ce22a2
  - path: Sources/Services/E1AgentStatusMonitor.swift
    sha: a28f39ef78644471d1dcf859aa2178f1b9ebd1fd
---

# E1 Transcript Recorder Hang

## Overview

初期実装では独立タイマーが 2 秒ごとに main スレッドで Ghostty SCREEN 全文を保持し、grapheme suffix diff（O(n²)）を行った。大きな scrollback で RAM 7 GB 超・CPU 125%・UI ハングが発生した。

## 症状

- アプリ全体が固まる
- メモリ使用量が GB 単位で急増
- Activity Monitor で kobaamd の CPU が常時高負荷

## 原因

1. main スレッドでの高頻度 SCREEN 全文読み取り
2. 前回全文 + 現行全文の文字列常駐
3. grapheme 単位の最長共通接尾辞探索

## 対策（現行）

| 対策 | 実装 |
|------|------|
| ポーリング統合・間引き | `E1AgentStatusMonitor`、transcript は 10 ティックに 1 回 |
| バイト diff | `E1TerminalTranscriptDelta`、接続探索上限 16 KB |
| メタデータのみ保持 | `E1TerminalScreenSnapshot.tailUTF8` 最大 32 KB |
| 再入防止 | `isRefreshing` ガード |
| アプリ非アクティブ時停止 | `pauseSampling()` |

## Invariants & Gotchas

- SCREEN 全文を `[String]` としてセッションごとに蓄積しない。
- transcript 用の別タイマーを復活させない。`E1AgentStatusMonitor` に統合済み。

## Sources

- [[e1-agent-status-monitor]]
- [[e1-terminal-transcript-store]]