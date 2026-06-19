# LLM-Wiki Index

## concepts/

- [E1 Terminal Lightweight + Convenience](concepts/e1-terminal-lightweight.md) — 軽量と利便性の両立方針（PTY は切替で止めない）

## modules/

- [E1 Terminal Memory Policy](modules/e1-terminal-memory-policy.md) — RAM/CPU/ディスク予算と suspend 条件
- [E1 Agent Status Monitor](modules/e1-agent-status-monitor.md) — エージェント状態ポーリング + transcript サンプリング
- [E1 Terminal Transcript Store](modules/e1-terminal-transcript-store.md) — ディスク transcript 追記・ローテーション
- [HTML Preview via External Chromium](modules/html-preview-chromium.md) — localhost HTTP + 外部 Chrome `--app=` プレビュー (v0.4.5)

## flows/

- [E1 Session Switch Terminal Lifecycle](flows/e1-session-switch-terminal.md) — セッション切替時の PTY 保持と eviction

## gotchas/

- [E1 Transcript Recorder Hang](gotchas/e1-transcript-recorder-hang.md) — SCREEN 全文の main スレッド O(n²) diff によるハング
- [Workspace FSEvents Memory Storm](gotchas/workspace-fsevents-memory-storm.md) — transcript.log 連鎖による GB 級 RAM 膨張と v0.4.6 対策