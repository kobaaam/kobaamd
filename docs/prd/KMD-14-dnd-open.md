# PRD: KMD-14 — ファイルをDnDで表示する

## 1. 目的

kobaamd のメインウィンドウ全体をドラッグ＆ドロップのターゲットにし、Finder からファイルをドロップするだけで新しいタブで開けるようにする。複数ファイルの同時ドロップにも対応し、ドラッグオーバー中の視覚的フィードバックを追加する。

## 2. 背景

現状の `EditorView.swift` には `.onDrop` が実装されているが、以下の問題がある：
- `providers.first` のみ処理するため複数ファイルドロップ非対応
- `isTargeted: nil` のためドラッグオーバー中の視覚的フィードバックなし
- エディタエリア外（サイドバー・ツールバー・プレビューペイン）にドロップしても反応しない

macOS 標準的なドキュメントアプリはウィンドウ全体をDnDターゲットにしている。

## 3. 機能概要

- `MainWindowView` の最外 ZStack に `.onDrop` を付与し、ウィンドウ全体をターゲットに
- 複数ファイルのドロップを並列処理してタブを順次開く
- ドラッグオーバー中は点線ボーダー + 半透明オーバーレイ + "Drop to open" テキストを表示
- フォルダドロップ時は `FileTreeViewModel.addFolder()` 経由でサイドバーに追加

## 4. スコープ

**M**: EditorView の既存 onDrop 改善 + MainWindowView へのウィンドウ全体DnD追加

## 5. 受け入れ条件

1. Finder から `.md` ファイルを kobaamd のウィンドウにドロップすると、新しいタブでそのファイルが開く
2. 複数の `.md` ファイルを同時にドロップすると、タブが増え最後のファイルがアクティブになる
3. ドラッグオーバー中に点線の視覚フィードバックが表示され、ドロップ後またはキャンセル後に消える
4. 非対応ファイル型 (`.png` 等) はドロップを無視しクラッシュしない
5. `swift build` が通る

## 6. 影響範囲マップ

### 変更対象ファイル（確定）

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `Sources/Views/MainWindowView.swift` | 変更 | `.onDrop` 追加、`@State isTargeted` 追加、オーバーレイ View 追加 |
| `Sources/Views/Editor/EditorView.swift` | 変更 | 複数ファイル対応（`providers.first` → 全件ループ）、`isTargeted` を State で管理してオーバーレイ表示 |

### 変更しないファイル（明示）

| ファイル | 理由 |
|---|---|
| `Sources/App/AppViewModel.swift` | `openInTab` はそのまま流用 |
| `Sources/Services/FileService.swift` | `readFile(at:)` はそのまま流用 |
| `Sources/App/kobaamdApp.swift` | Finder 経由オープンの AppDelegate 処理は変更不要 |
| `Sources/Views/Diff/DiffView.swift` | Diff 画面の独立した onDrop は変更しない |
| `Sources/Views/Sidebar/SidebarView.swift` | サイドバーの他タブ（Outline, Todo, Search）に触れない |

### 変更してはいけない箇所

- `SidebarView` の Outline / Todo / Search タブの実装
- `NSTextViewWrapper` の内部実装（スクロール比率・行ハイライト・AIインライン補完）
- `DiffView` / `DiffInlineView` の onDrop 実装
- `AppDelegate` の `application(_:open:)` / `application(_:openFile:)` の実装
- `AppState.pendingOpenFileURL` を使った既存のオープン経路
