# KMD-20: ファイルテンプレートシステム（AI プリセット付き新規ドキュメント作成）

## 1. 背景・目的

kobaamd のビジョン「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」において、「AI と一緒に書き始める」体験の起点を強化する機能。現在の「新規ファイル（Cmd+N）」は空ファイルを生成するのみ。テンプレートシステムを導入し、ユースケースを選ぶだけで AI フレンドリーな骨格が即座に挿入される。

## 2. 機能要件

### 必須要件

- `Cmd+Shift+N` でテンプレート選択シートを表示（`Cmd+N` は従来通り空タブ）
- ビルトインテンプレート 5 種同梱: 空ファイル / README / 議事録 / 技術仕様書 / 日記
- ユーザーカスタムテンプレートを `~/.config/kobaamd/templates/` から読み込み
- `FileService.swift` に `loadTemplates() -> [DocumentTemplate]` 追加
- テンプレート選択後、内容を新規タブの初期コンテンツとして設定
- `SettingsView.swift` に「テンプレートフォルダを Finder で開く」ボタン追加

### オプション要件

- テンプレート選択シートでの検索フィルター
- テンプレートのプレビュー（選択時に内容表示）

## 3. 受け入れ条件

- [ ] `Cmd+Shift+N` でテンプレート選択シートが表示される
- [ ] テンプレート選択シートで「README」を選んで「作成」を押すと、README テンプートの内容が挿入された新規タブが開く
- [ ] `~/.config/kobaamd/templates/` に `.md` ファイルを追加すると、カスタムセクションに表示される
- [ ] `SettingsView` に「テンプレートフォルダを Finder で開く」ボタンがある
- [ ] `swift build` でビルドエラーが 0 件

## 6. テスト戦略

- 単体テスト: `FileService.loadTemplates()` のユニットテスト
- 既存テスト: 全テスト pass

## 8. 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Models/DocumentTemplate.swift` | **新規** | テンプレートモデル定義 |
| `Sources/Services/FileService.swift` | 変更 | `loadTemplates()` メソッド追加 |
| `Sources/App/AppCommand.swift` | 変更 | `newFileFromTemplate` コマンド追加 |
| `Sources/App/AppViewModel.swift` | 変更 | `newTabFromTemplate(content:)` メソッド追加、テンプレートシート表示フラグ追加 |
| `Sources/App/kobaamdApp.swift` | 変更 | `Cmd+Shift+N` メニュー項目追加、Notification.Name 追加 |
| `Sources/Views/Editor/TemplatePickerView.swift` | **新規** | テンプレート選択シート UI |
| `Sources/Views/MainWindowView.swift` | 変更 | `.sheet` 追加、`onReceive` 追加 |
| `Sources/Views/Settings/SettingsView.swift` | 変更 | 「テンプレートフォルダを開く」ボタン追加 |
| `Sources/Resources/templates/` | **新規** | ビルトインテンプレートファイル（5件） |
| `Tests/kobaamdTests/FileServiceTests.swift` | 変更 | テンプレートロードのテスト追加 |

### 変更してはいけない箇所

- `Cmd+N` の既存動作（空タブを開く）— 変更不可
- `Cmd+T` の既存動作（空タブを開く）— 変更不可
- `AppViewModel.newTab()` のシグネチャ・挙動 — 変更不可（新メソッドで対応）
- `SnippetStore` / `QuickInsertView` — 無関係、触れない
- `EditorView` / `NSTextViewWrapper` — 無関係、触れない
- `AIService` / `AIChatViewModel` — 無関係、触れない
- `PreviewView` / `MermaidWebView` / `MarkdownWebView` — 無関係、触れない
- `DiffView` / `DiffViewModel` — 無関係、触れない
