# KMD-9: カラーテーマサポート（エディタ＋プレビュー）

## 1. 目的

エディタとプレビューのカラーテーマを切り替え可能にする。現在はハードコードされた Light テーマのみ。ユーザーが Light / Dark / Solarized Dark の3テーマから選択でき、プレビュー CSS とエディタの色が連動して変わる。

## 2. 背景

- README ロードマップに「Custom themes — Light/dark/custom color schemes」が明記
- 現在はシステム Dark モードに非対応。ハードコード色のみ
- Bear, iA Writer のようにテーマでブランドアイデンティティを持つ

## 3. 必須要件

1. `ColorTheme` enum を定義: `.light` (既存色), `.dark`, `.solarizedDark`
2. `AppState` に `selectedTheme` プロパティ追加（UserDefaults 永続化）
3. 設定画面 (`SettingsView`) にテーマ選択 Picker 追加
4. `HighlightService` がテーマに応じたシンタックスカラーを使用
5. `NSTextViewWrapper` がテーマに応じたエディタ背景色・テキスト色を使用
6. `MarkdownService.toHTML()` がテーマに応じた CSS を生成
7. `Color+Koba.swift` にテーマ別カラーパレットを定義

## 4. オプション要件（今回はスキップ）

- ユーザーカスタムテーマ（JSON/YAML で定義）
- テーマのインポート/エクスポート
- テーマのリアルタイムプレビュー（設定画面で）

## 5. 設計方針

- `ColorTheme` model が全テーマの色定義を持つ（Single Source of Truth）
- `AppState.selectedTheme` を `@Observable` で配信
- 各 View / Service はテーマから色を取得
- 既存のハードコード色は `ColorTheme.light` に移行するが、`Color+Koba.swift` の既存トークンはそのまま残す（他で使われているため）

## 6. 受け入れ条件

- [ ] 設定画面でテーマを切り替えるとエディタ・プレビュー両方の色が変わる
- [ ] テーマ選択が再起動後も保持される（UserDefaults）
- [ ] Light テーマは既存の見た目と同一
- [ ] Dark テーマでエディタ背景が暗色、テキストが明色になる
- [ ] ビルドが通る (`swift build`)
- [ ] 既存テストが通る (`swift test`)

## 7. 非目標

- システムの Dark Mode 自動追従（将来対応）
- TreeSitter ベースのシンタックスハイライト統合

## 8. 影響範囲マップ

### 新規追加ファイル

| ファイル | 内容 |
|---|---|
| `Sources/Models/ColorTheme.swift` | テーマ enum + カラーパレット定義 |

### 変更ファイル

| ファイル | 変更内容 | 影響する機能 |
|---|---|---|
| `Sources/Services/AppState.swift` | `selectedTheme` プロパティ追加 | 全 View（テーマ参照） |
| `Sources/Services/HighlightService.swift` | テーマ対応色に変更 | エディタのシンタックスハイライト |
| `Sources/Views/Editor/NSTextViewWrapper.swift` | テーマ対応の背景色・テキスト色 | エディタ表示 |
| `Sources/Services/MarkdownService.swift` | テーマ対応 CSS 生成 | プレビュー表示 |
| `Sources/Views/Settings/SettingsView.swift` | テーマ選択 Picker 追加 | 設定画面 |
| `Sources/Views/Editor/EditorView.swift` | テーマ対応の背景色 | エディタ外観 |
| `Sources/ViewModels/PreviewViewModel.swift` | テーマ変更時にシェル HTML 再生成 | プレビュー再描画 |

### 変更してはいけない箇所

- `Color+Koba.swift` の既存静的トークン（`kobaInk`, `kobaPaper` 等）は削除・リネーム不可（サイドバー・タブバー等で多数使用）
- `AppCommand` enum の既存 case は変更不可
- `Notification.Name` の既存定義は変更不可
- `EditorTab`, `FileNode` など既存 Model の構造は変更不可
- `MarkdownService` のレンダリングロジック（HTML 構造生成部分）は変更不可。CSS のみ差し替え
- `HighlightService.highlight()` のメソッドシグネチャは変更不可
