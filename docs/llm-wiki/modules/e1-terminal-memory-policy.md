---
title: "E1 Terminal Memory Policy"
slug: e1-terminal-memory-policy
type: module
updated_commit: 8d67c7c210b1bfd44a72ab19b1d07d3b691e3b62
updated_at: 2026-06-13
freshness: current
sources:
  - path: Sources/Services/E1TerminalMemoryPolicy.swift
    sha: 20eb0ac8ef9644cea6c00ea5f187374d0dd618de
---

# E1 Terminal Memory Policy

## Overview

`E1TerminalMemoryPolicy` は E1 ターミナルの RAM・CPU・ディスク予算を定数で集中管理する。実装の分散を防ぎ、軽量化チューニングの単一入口にする。

## Key Components

| 定数 | 値 | 用途 |
|------|-----|------|
| `scrollbackLimit` | `"2m"` | Ghostty スクロールバック上限（RAM） |
| `maxActiveTerminals` | `6` | 同時 PTY 上限。超過時のみ LRU suspend |
| `diskTranscriptMaxBytes` | 100 MB | worktree 配下 transcript ローテーション |
| `agentStatusPollInterval` | 3 s | エージェント状態（viewport）ポーリング |
| `transcriptEveryNTicks` | 10 | SCREEN 全文読み取りは 10 ティックに 1 回（≈30 s） |

ディスクパス: `<worktree>/.kobaamd/transcript.log`

## Invariants & Gotchas

- セッション切替は `maxActiveTerminals` の eviction トリガーに**含めない**（[[e1-terminal-lightweight]]）。
- scrollback を大きくすると RAM が膨らむ。長いログは transcript へ逃がす。

## Sources

- `Sources/Services/E1TerminalMemoryPolicy.swift`