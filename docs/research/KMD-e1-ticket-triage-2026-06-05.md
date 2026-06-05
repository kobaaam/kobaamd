---
status: active
updated: 2026-06-05
owner: Grok（棚卸し）/ Gemini（UX 要件ドラフト）
branch: feature/e1-reconcept-shell
---

# E1 Re-concept チケット棚卸し（2026-06-05）

## 前提（人間フィードバック）

- Tracer Bullet（E1 シェル + Local セッション + ターミナル + Viewer タブ）は **成功体感**
- git worktree セッションは一旦 **非表示**（`SessionCoordinator.gitWorktreeEnabled = false`）
- 次の焦点: **中央 Terminal（メイン）** と **右 Preview / Editor** の共存 UX

## Grok 判定 — KMD-217〜233

| ID | 判定 | 理由 |
|----|------|------|
| **KMD-217** | **残す（Epic 更新）** | Phase 1 完了 → Phase 2（Tri-pane UX）へスコープ追記 |
| **KMD-218** | **残す → Reviewed** | PRD/ADR は実装の参照源。Local セッションへ差分追記は Phase 2 PRD で |
| **KMD-219** | **Done** | SwiftTerm spike + 本番配線済み（`8935c4b`） |
| **KMD-220** | **Reviewed** | 3 ペインシェル + リサイズ |
| **KMD-221** | **Reviewed** | `WorktreeService` 実装済み。UI は Local セッションにピボット |
| **KMD-222** | **Reviewed** | Session リスト + 追加/削除 |
| **KMD-223** | **Reviewed** | scoped Files |
| **KMD-224** | **Reviewed** | `SessionCoordinator` |
| **KMD-225** | **Done** | 埋め込みターミナル MVP |
| **KMD-226** | **Done** | セッション別 PTY + LRU |
| **KMD-227** | **Done** | Viewer タブ（Rendered/Source/D2/Diff/CSV） |
| **KMD-228** | **Done** | NEW バッジ + 自動オープン |
| **KMD-229** | **残す（文言修正）** | worktree → **active session** スコープの Quick Open |
| **KMD-230** | **残す（Backlog）** | Outline/Backlinks/Tags/AI Chat の E1 配置は Phase 3 |
| **KMD-231** | **Reviewed** | `useE1Shell` + DEBUG デフォルト ON |
| **KMD-232** | **残す（分割）** | 単体テスト済み。Tart E2E は別途 |
| **KMD-233** | **残す（Backlog）** | Phase C（旧 UI 削除）まで保留 |

### Canceled にしないもの

- **KMD-221/222** の worktree 文言は将来復活前提。コードは残しチケットは完了扱い。

## Gemini ドラフト — Phase 2 UX 方針（Preview × Editor × Terminal）

### 現状の摩擦

| 摩擦 | 詳細 |
|------|------|
| 右ペインがタブ排他 | Source（Editor）と Rendered（Preview）を同時に見られない |
| 中央ターミナルが主役 | エージェント作業中も成果物を横で追いたい |
| フォーカス不明 | ターミナル vs エディタでショートカットの行き先が曖昧 |

### 推奨 UX（2 段階）

**Phase 2a（最小）— 右ペイン内 Split**

```
+----------+---------------------------+------------------------+
| Sessions |                           | [Rendered][Source]...  |
| Files    |      Terminal (main)      | +----------+---------+ |
|          |                           | | Rendered | Source  | |
|          |                           | | (preview)| (edit)  | |
+----------+---------------------------+------------------------+
```

- 右ペイン: 上段 Rendered / 下段 Source（または左右 Split、幅記憶）
- タブは D2 / Diff / CSV は従来通り単独タブ
- `.md` 選択時のみ Split モード自動

**Phase 2b（任意）— フォーカスゾーン**

- `⌘1` Terminal / `⌘2` Viewer / `⌘3` Files フォーカス
- `⌘\\` で右 Split のオンオフ（旧 MainWindow の Split 記憶を流用）

### 新規チケット（Linear — 起票済み）

| ID | タイトル | 状態 |
|----|----------|------|
| [KMD-234](https://linear.app/kobaan/issue/KMD-234) | [E1-P2] PRD: Terminal × Editor × Preview 共存 UX | Todo |
| [KMD-235](https://linear.app/kobaan/issue/KMD-235) | [E1-P2] 右ペイン Source\|Rendered 同時表示 Split | Backlog |
| [KMD-236](https://linear.app/kobaan/issue/KMD-236) | [E1-P2] フォーカスルーティングとショートカット | Backlog |
| [KMD-237](https://linear.app/kobaan/issue/KMD-237) | [E1-P2] 拡張子別デフォルト Viewer レイアウト | Backlog |
| [KMD-238](https://linear.app/kobaan/issue/KMD-238) | [E1-P2] merge feature/e1-reconcept-shell → main | Todo |
| [KMD-239](https://linear.app/kobaan/issue/KMD-239) | [E1-P3] git worktree セッション（Settings から復活） | Backlog |

## 依存

```
KMD-238 (merge) は Phase 2a の前でも可（並行）
KMD-234 (PRD) → KMD-235, KMD-236, KMD-237
KMD-229 は KMD-224 完了後いつでも
```