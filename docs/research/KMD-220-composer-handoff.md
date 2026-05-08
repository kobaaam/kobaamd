---
linear: KMD-220, KMD-231
author: Grok (設計)
implementer: Composer
branch: feature/e1-reconcept-shell
base: main
---

# KMD-220 + KMD-231 — Composer 実装仕様

## 目的

E1 三ペインの**プレースホルダ UI**を feature flag 付きで入れる。既存 `MainWindowView` は **flag off 時のみ**そのまま使う。

## 非ゴール（本 PR ではやらない）

- SwiftTerm / PTY（KMD-225）
- git worktree パース（KMD-221）
- SessionCoordinator（KMD-224）
- Viewer タブの実配線（KMD-227）

## 1. Feature flag

`AppState` に追加:

```swift
var useE1Shell: Bool {
    get { defaults.bool(forKey: "useE1Shell") }
    set { defaults.set(newValue, forKey: "useE1Shell") }
}
```

- デフォルト: `false`（Phase A）
- `SettingsView` に Toggle「E1 シェル（実験的）」+ 短い説明文
- `static` フォワード on `AppState.shared`（他設定と同パターン）

## 2. エントリ分岐

`kobaamdApp.swift` の `WindowGroup` 内:

```swift
Group {
    if AppState.shared.useE1Shell {
        E1MainWindowView()
    } else {
        MainWindowView()
    }
}
.environment(appViewModel)
```

`MainWindowView` は**リネームしない**（差分最小）。

## 3. 新規ファイル（`Sources/Views/E1/`）

| ファイル | 責務 |
|----------|------|
| `E1MainWindowView.swift` | 3 ペイン HStack、既存 `KobaDivider` / `SplitDivider` パターン踏襲 |
| `E1SessionRailView.swift` | 上: Sessions プレースホルダ、下: Files プレースホルダ、縦分割 |
| `E1TerminalPlaceholderView.swift` | 中央「Terminal (PTY) — KMD-225」 |
| `E1ViewerPlaceholderView.swift` | 右「Viewer tabs — KMD-227」 |

### レイアウト定数（ADR-0010 継承）

- 左レール: 初期幅 `240pt`、最小幅 `200pt`
- 右 Viewer: 初期幅 `360pt`、最小幅 `280pt`
- 中央: 残り全部
- 左レール内: Sessions 上 `42%` / Files 下（`GeometryReader` + `VStack`）
- 色: `Color.kobaSurface`, `Color.kobaPaper`, `Color.kobaLine`, `Color.kobaMute`（既存）

### E1MainWindowView 骨格

```
HStack {
  E1SessionRailView.frame(width: leftW)
  KobaDivider + ドラッグで leftW 変更（SplitDivider と同様の Binding）
  E1TerminalPlaceholderView.frame(maxWidth: .infinity)
  KobaDivider + ドラッグで rightW
  E1ViewerPlaceholderView.frame(width: rightW)
}
```

- `@Environment(AppViewModel.self)` は付けるが未使用で OK（後続チケット用）
- ツールバーは最小: タイトル「kobaamd (E1)」程度で可。既存コマンドは `MainWindowCommandReceiver` を**共通化できれば** `E1MainWindowView` にも `.modifier` で付与（Save / Open Folder 等が動くとよい）

## 4. 受け入れ条件（PR にチェック）

- [ ] `useE1Shell == false` → 現行 UI が変わらない
- [ ] `useE1Shell == true` → 3 ペインが表示され、左右リサイズで崩れない
- [ ] `swift build` 成功
- [ ] 既存 `swift test` が落ちない（新規テストは任意: `AppState` flag の get/set のみ可）

## 5. README 追記（1 段落）

Settings で「E1 シェル（実験的）」を ON にすると開発中レイアウトが開く旨。デフォルト OFF。

## 6. 参照

- PRD: `docs/prd/KMD-218-e1-reconcept.md` §3–5
- ADR: `docs/adr/0013-e1-terminal-session-shell.md`
- モック: `.mockups/prototype-e1-flow.html`

## 7. コミットメッセージ案

```
feat(e1): add E1 shell placeholders behind useE1Shell flag (KMD-220, KMD-231)
```