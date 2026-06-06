# ADR-0013: E1 Terminal + Session Shell

- **Status**: accepted
- **Date**: 2026-06-04
- **Deciders**: 人間 / Gemini 2.5 Flash（起草）
- **Related**: ADR-0010, ADR-0002, KMD-217, KMD-218

## Context

kobaamd の現行シェル（ADR-0010）は **Sidebar | Editor | Preview (+ AI Chat)** の Markdown 執筆向きレイアウト。Re-concept プロトタイプ（E1）では **Session rail | Terminal | Viewer** に再編し、セッション単位を **git worktree** とする。

制約:

- macOS 14+、SwiftPM、Hardened Runtime（ad-hoc codesign）
- App Sandbox は未启用（KMD-40 骨格のみ）— PTY は当面フルアクセス前提
- 既存 `@Observable` MVVM、AppKit ブリッジ（ADR-0002）を維持

## Decision

1. **E1 シェル**を `MainWindowView` の新分岐（feature flag）として導入する。
2. **`SessionCoordinator`** が active session を単一の真実の源とし、FileTree / Terminal / ViewerTabs / Editor（Source タブ）を同期する。
3. **中央ペインは常に PTY ターミナル**。Markdown 編集は **右ペイン Source タブ**（PRD KMD-218 §5）。
4. **WorktreeService** が `git worktree list --porcelain` をパースして Session 一覧を供給する。
5. レイアウト実装は ADR-0010 と同様 **HStack + GeometryReader + KobaDivider** を継承し、NavigationSplitView は使わない。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|--------|---------|-----------|----------|
| 現行 3 ペイン維持 + ターミナル別ウィンドウ | 変更最小 | 動線が分断、E1 プロト検証と不一致 | リコンセプト目的に合わない |
| NavigationSplitView 3 列 | 標準 API | 列数・幅制御が ADR-0010 と同様に不足 | 0010 で却下済み |
| E2 デュアルレール（Session×2） | 比較 UI に有利 | 複雑、プロトで E1 に収束済み | NOTES.md で不採用 |
| 中央 Terminal↔Editor トグル | 画面節約 | ターミナル中心が弱まる | PRD で不採用 |

## Consequences

### Positive

- エージェント作業と成果物閲覧が 1 ウィンドウに収まる
- worktree 単位の隔離が UI と一致する
- 既存 Preview / D2 / CSV / Diff を右ペインに集約再利用できる

### Negative

- `MainWindowView` の複雑度が一時的に倍化（flag 併存期）
- PTY 複数保持は FD・メモリコスト（上限ポリシー必須）

### Risks

| リスク | 緩和 |
|--------|------|
| PTY FD リーク | セッション eviction、終了時 kill、Instruments 手順 |
| 巨大 worktree で切替遅延 | ツリーの遅延ロード、計測（PerfLogger） |
| 将来 Sandbox 化 | KMD-40 完了後に PTY 制限の follow-up ADR |

## References

- [KMD-218 PRD](../prd/KMD-218-e1-reconcept.md)
- [KMD-219 Spike](../research/KMD-219-terminal-embed-spike.md)
- `.mockups/NOTES.md`