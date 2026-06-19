# LLM-Wiki Change Log

## [2026-06-13] init | llm-wiki
- `docs/llm-wiki/` スキャフォールドを新設

## [2026-06-13] create | e1-terminal-lightweight
- E1 ターミナル「軽量 + 利便性」方針を concepts に記録

## [2026-06-13] create | e1-terminal-memory-policy
- `E1TerminalMemoryPolicy` の予算定数と suspend 条件

## [2026-06-13] create | e1-agent-status-monitor
- エージェント状態 + transcript の統合ポーリング

## [2026-06-13] create | e1-terminal-transcript-store
- ディスク transcript 追記・差分・ローテーション

## [2026-06-13] create | e1-session-switch-terminal
- セッション切替フロー（PTY 保持）

## [2026-06-13] create | e1-transcript-recorder-hang
- transcript 実装のハング原因と対策

## [2026-06-18] update | html-preview-chromium
- HTML プレビューを Chromium（Google Chrome 等）連携に切り替え。localhost プレビューサーバ経由で Chrome と同じレンダリングを実現。

## [2026-06-19] create | html-preview-chromium
- v0.4.5 の Chromium + localhost HTTP プレビュー方式を modules に文書化

## [2026-06-19] create | workspace-fsevents-memory-storm
- 39GB メモリ incident の因果と v0.4.6 debounce / .kobaamd 除外対策を gotchas に記録