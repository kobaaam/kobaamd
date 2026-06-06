---
linear: KMD-219
date: 2026-06-04
author: Grok（Gemini 補完予定）— 初版
status: draft
---

# KMD-219: 埋め込みターミナル実装方式 Spike

## 目的

E1 中央ペインの PTY 実装を選定し、KMD-225（MVP）のブロッカーを外す。

## 比較

| 方式 | SPM | macOS 統合 | リサイズ / フォント | セッション複数 | メンテ |
|------|-----|------------|---------------------|----------------|--------|
| **SwiftTerm** | ✅ `swiftterm` | NSViewRepresentable 実績多数 | 組み込み | インスタンス per PTY | 活発 |
| 自前 PTY + `NSTextView` | なし | `fork` + `openpty` + AppKit | 自前実装大 | 可能だがコスト高 | 自社負担 |
| `TerminalView` (SwiftTerm 系 fork) | 要確認 | 同上 | 同上 | 同上 | 要調査 |

## 推奨

**第 1 候補: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)**（`LocalProcessTerminalView`）

**第 2 候補**: 自前 PTY + 薄い `NSView` ラッパ（SwiftTerm が Sandbox / 署名で詰まった場合のみ）

### 理由（SwiftTerm）

- macOS 向け LocalProcess ターミナルが既にあり、**KMD-225 は「配線」が主仕事**になる
- SPM 追加のみで kobaamd の依存方針と整合
- スクロールバック・カーソル・リサイズはライブラリ任せ

### Hardened Runtime

- 子プロセス起動（user shell）は ad-hoc 署名の現行配布と整合
- 将来 Sandbox 有効化時は **PTY 制限の別チケット**が必要（KMD-40 フォロー）

## リソース見積（[推測]）

| 項目 | 1 セッション | 8 セッション（上限） |
|------|-------------|---------------------|
| PTY FD | 2〜3 | 16〜24 |
| スクロールバック | ≤256KB 設定 | ≤2MB |
| 子プロセス | 1 shell | 8（eviction で実質 ≤8） |

## 統合ステップ（KMD-225 → 226）

1. `Package.swift` に SwiftTerm 追加、`swift build` 確認
2. `TerminalPaneView`（NSViewRepresentable）を中央ペインに配置、cwd = worktree root
3. `SessionCoordinator` から `startProcess(executable: userShell)` を呼ぶ
4. リサイズ: `GeometryReader` の size 変更を terminal へ伝播
5. KMD-226: sessionId → terminal インスタンス辞書、切替で `isHidden` swap + 未使用 eviction

## 却下条件（再調査トリガー）

- Apple Silicon で `LocalProcessTerminalView` がクラッシュする
- コード署名 / Hardened Runtime で子プロセス起動が拒否される
- SPM 解決が tree-sitter 等と競合する

## 結論

**KMD-225 は SwiftTerm 前提で着手してよい。** 実装開始前に `swift package resolve` と最小 PoC（1 ウィンドウで `bash -l`）を 30 分以内で確認する。

## 参照

- [SwiftTerm LocalProcess ドキュメント](https://github.com/migueldeicaza/SwiftTerm)
- [KMD-218 PRD](../prd/KMD-218-e1-reconcept.md)