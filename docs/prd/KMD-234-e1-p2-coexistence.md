---
linear: KMD-234
parent: KMD-217
status: approved-for-implementation
created_at: 2026-06-05
---

# E1 Phase 2: Terminal × Editor × Preview 共存 UX

## 1. 問題

Phase 1（KMD-217〜228）で E1 シェルは成立した。中央ターミナルでエージェント作業しつつ、右ペインで成果物を追う体験が主役になった。

一方、右ペインは **Rendered / Source がタブ排他** のため、プレビューと編集を同時に見られない。旧 MainWindow の Split モードに比べ、E1 では執筆＋確認の往復コストが上がっている。

## 2. 目標

| 目標 | 指標 |
|------|------|
| エージェント作業中も成果物を横で追える | `.md` 選択時、Rendered+Source を 1 画面で表示 |
| 中央ターミナルを主役のまま | レイアウト 3 列は維持。右ペイン内だけ Phase 2 で拡張 |
| 既存 Viewer タブを壊さない | D2 / Diff / CSV は単独タブのまま |

## 3. 非目標（Phase 2）

- git worktree セッション UI 復活（→ KMD-239）
- Outline / Backlinks / AI Chat の E1 配置（→ KMD-230）
- 旧 MainWindow 削除（→ KMD-233）
- フォーカスゾーン・⌘1/2/3（→ KMD-236、Phase 2b）

## 4. レイアウト決定（Phase 2a）

```
右ペイン（.md 選択時）
┌─────────────────────────┐
│ [Rendered*][Source*] D2 │  ← * = Split モードで両方ハイライト
├─────────────────────────┤
│ Rendered (PreviewView)  │  ← 上 45% 初期（リサイズ可）
├─────────── divider ─────┤
│ Source (EditorView)     │  ← 下 55%
└─────────────────────────┘
```

| ファイル種別 | 右ペイン既定 |
|-------------|-------------|
| `.md` / `.markdown` | **縦 Split**（Rendered 上 / Source 下） |
| `.d2` | D2 タブ単独 |
| `.csv` | CSV タブ単独 |
| その他 | Source タブ単独 |
| Diff | Diff タブ（任意ファイル） |

## 5. タブバー挙動

- Rendered / Source を押しても **同じ Split ペイン** を表示（排他切替しない）
- D2 / Diff / CSV 選択時は従来どおり単独コンテンツ
- Split 比率は `UserDefaults` キー `e1ViewerMdSplitFraction`（0.25〜0.75、既定 0.45）

## 6. 旧 MainWindow との互換

| 旧 | E1 Phase 2 |
|----|------------|
| `previewMode == .split` | 右ペイン MD Split に相当 |
| `⌘\\` Split トグル | Phase 2b（KMD-236）で E1 に移植 |
| `splitFraction`（横） | E1 は **縦** Split（右ペイン幅が狭いため） |

## 7. 実装チケット切り出し

| ID | 内容 | 依存 |
|----|------|------|
| **KMD-235** | MD 縦 Split + リサイズ + タブバー連動 | 本 PRD |
| **KMD-236** | フォーカスゾーン・⌘1/2/3・⌘\\ Split トグル | KMD-235 |
| **KMD-237** | 拡張子別デフォルトの設定化・テスト | KMD-235 |
| **KMD-238** | `feature/e1-reconcept-shell` → main | 並行可 |

## 8. 受け入れ基準（Phase 2a）

- [x] 本 PRD が `docs/prd/` に存在し KMD-235〜237 から参照できる
- [ ] `.md` を開くと Rendered と Source が同時表示される（KMD-235）
- [ ] 境界ドラッグで上下比率が変わり、再起動後も保持される（KMD-235）
- [ ] `.csv` / `.d2` 選択時は Split ではなく専用タブのみ（KMD-235/237）

## 9. 参照

- [KMD-218 E1 Re-concept PRD](./KMD-218-e1-reconcept.md)
- [ADR-0013 E1 Terminal Session Shell](../adr/0013-e1-terminal-session-shell.md)
- [E1 棚卸し](../research/KMD-e1-ticket-triage-2026-06-05.md)