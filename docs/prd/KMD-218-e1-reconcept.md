---
linear: KMD-218
status: draft
created_at: 2026-06-04
author: Gemini 2.5 Flash（起草）+ 人間レビュー待ち
---

# E1 Re-concept: Terminal + Knowledge Viewer

## 1. 背景・目的

kobaamd は Markdown エディタであると同時に、自律開発パイプラインの実験場である。現行 UI（左サイドバー | エディタ | プレビュー | AI チャット）は執筆向きだが、**エージェント実行（ターミナル）と成果物閲覧（md/D2/diff）が分断**されている。

プロトタイプ（`.mockups/NOTES.md`, 2026-05-29）で **E1「二段レール」** を採用。本 PRD は実装チケット（KMD-220〜）の単一の参照源とする。

## 2. ターゲットユーザーとユースケース

- **AI 駆動開発者**: worktree ごとにエージェントを走らせ、生成 md/D2 をすぐ右ペインで確認する
- **ナレッジワーカー**: 同一リポジトリ内の複数 worktree（機能ブランチ）をセッション単位で切り替える
- **既存 kobaamd ユーザー**: feature flag で旧 UI に戻せる（移行期）

## 3. E1 レイアウト

```
+------------------------------------------------------------------+
| Sessions (worktree)  |                    | Viewer tabs         |
|  - feature/foo       |                    | [Rendered][Source]  |
|----------------------|     Terminal       | [D2][Diff][CSV]     |
| Files (scoped)       |        (PTY)       |                     |
|  outline/backlinks   |                    | (+ AI drawer 任意)  |
+------------------------------------------------------------------+
```

| ペイン | 責務 |
|--------|------|
| 左上 | Session 一覧（git worktree） |
| 左下 | スコープファイルツリー + Outline / Backlinks / Tags |
| 中央 | インタラクティブシェル（cwd = active worktree root） |
| 右 | 成果物ビューア（タブ） |

## 4. Session モデル

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `id` | UUID | セッション ID |
| `name` | String | 表示名（worktree フォルダ名から自動生成可） |
| `worktreePath` | URL | worktree ルート |
| `branchName` | String? | `git branch --show-current` キャッシュ |
| `terminalSnapshot` | Data? | PTY スクロールバック（上限あり） |
| `fileTreeState` | Data? | 展開・選択状態 |
| `viewerTabsState` | Data? | 開タブ・選択タブ |
| `lastAccessedAt` | Date | LRU 用 |

**切替時**: 上記状態を丸ごと swap。未保存エディタは既存 autosave / 確認ダイアログ方針に従う。

## 5. Markdown エディタの配置（決定）

**右ペイン Viewer の「Source」タブ**に `EditorView`（NSTextView ラップ）を配置する。

| 案 | 棄却理由 |
|----|----------|
| 中央 Terminal↔Editor トグル | ターミナル中心の E1 コンセプトと矛盾 |
| 右ペイン固定 Split（Editor\|Preview） | D2/Diff/CSV タブの柔軟性低下 |
| 4 ペイン追加 | 画面効率・複雑性 |

Rendered / Source は同一ファイルに対しタブ切替。⌘S / TreeSitter ハイライトは Source タブのみ。

## 6. 既存機能の行き先

| 機能 | E1 での配置 |
|------|-------------|
| FileTree | 左下（worktree スコープ） |
| Outline / Backlinks / Tags | 左下サブパネル or 折りたたみ |
| Editor | 右 Source タブ |
| Preview / D2 / CSV | 右 Rendered / D2 / CSV タブ |
| Diff | 右 Diff タブ（⌘D） |
| Quick Open | ⌘P、active worktree のみ |
| AI Chat | 右端ドロワー 320pt（⌘⇧E）— 初期は現行維持 |
| AI Inline | Source タブ選択時のみ |
| Settings / Help | 現行メニュー維持 |
| Autosave / Keychain | 変更なし |

## 7. 機能要件

### 必須

- E1 3 ペインシェル（KMD-220）
- worktree 一覧と Session 選択（KMD-221, 222）
- スコープツリー + 切替オーケストレーション（KMD-223, 224）
- 埋め込みターミナル MVP → マルチ PTY（KMD-225, 226）
- Viewer タブ統合（KMD-227）
- 成果物 NEW + 自動オープン（KMD-228）
- feature flag `UseE1Shell`（KMD-231）

### オプション（Phase 5+）

- 新 worktree 作成（Session レールの +）
- セッション間ファイル DnD 禁止（明示）

## 8. 非機能要件

| 項目 | 目標 |
|------|------|
| セッション切替 | 体感 ≤ 300ms（1 万ファイル worktree 除く） |
| 同時 PTY 数 | デフォルト最大 8、超過時 LRU で suspend |
| メモリ | セッションあたりターミナルバッファ上限 256KB（調整可） |
| a11y | Session 名・タブ名が VoiceOver で読める |
| セキュリティ | PTY はユーザー shell をそのまま起動（Sandbox 化時は別 ADR） |

## 9. 受け入れ条件

- [ ] E1 レイアウトで 3 ペインがリサイズ可能
- [ ] worktree 2 つ以上で Session 切替が tree / terminal / viewer を一括更新
- [ ] 中央ターミナルで `pwd` が active worktree root
- [ ] .md を開くと Rendered と Source タブが使える
- [ ] 新規 .md 作成でツリーに NEW、自動オープン設定が動く
- [ ] ⌘P が他 worktree を出さない
- [ ] feature flag off で現行 MainWindowView に戻れる
- [ ] `swift build` / `swift test` / 主要 E2E smoke が通る

## 10. feature flag 移行（3 フェーズ）

1. **Phase A**: flag off デフォルト、E1 は開発者のみ
2. **Phase B**: flag on デフォルト、旧 UI は 1 リリース併存
3. **Phase C**: 旧 UI 削除、README を E1 前提に更新（KMD-233）

## 11. 影響範囲マップ

| パス | 変更 |
|------|------|
| `Sources/Views/MainWindowView.swift` | E1 シェル分岐 |
| `Sources/Views/E1/`（新規） | SessionRail, TerminalPane, ViewerTabs |
| `Sources/ViewModels/SessionCoordinator.swift`（新規） | 切替オーケストレーション |
| `Sources/Services/WorktreeService.swift`（新規） | git worktree 一覧 |
| `Sources/Views/Sidebar/FileTreeView.swift` | root スコープ |
| `Sources/Views/Preview/*` | Viewer タブから呼び出し |
| `Package.swift` | ターミナル依存追加（KMD-219 参照） |

**触らない（初期）**: Sparkle、Keychain、MCP CLI、`scripts/linear/*`

## 12. テスト戦略

- 単体: WorktreeService パース、SessionCoordinator 状態機械
- UI: Session 切替のスナップショット（SwiftUI Preview）
- E2E: KMD-232（2 worktree fixture）

## 13. 参照

- Epic [KMD-217](https://linear.app/kobaan/issue/KMD-217)
- ADR [0013-e1-terminal-session-shell.md](../adr/0013-e1-terminal-session-shell.md)
- Spike [KMD-219-terminal-embed-spike.md](../research/KMD-219-terminal-embed-spike.md)
- Project [Re-concept](https://linear.app/kobaan/project/re-concept-e1-terminal-knowledge-viewer-ecd569d654cb)