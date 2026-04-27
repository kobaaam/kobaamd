# PRD: KMD-11 — Markdown Auto-Formatter

## 1. 目的

AI が生成した Markdown（見出しレベルの不統一・連続する空白行・リストインデントのブレ・末尾スペース等）を、⌘⇧F 一発で整形できる機能を追加する。AI との共同執筆フローをスムーズにするための核心機能。

## 2. 背景

ChatGPT / Claude / Gemini が生成する Markdown は「構文的には正しいが視覚的に乱れた」状態になりやすい。現状 kobaamd には整形機能がなく、ユーザーは手動修正か外部ツール（prettier / markdownlint）に頼る必要がある。

## 3. 想定ユーザー

- **ペルソナ A**: AI ヘビーユーザー — 生成テキストを貼り付けてすぐ整形したい
- **ペルソナ B**: ドキュメントレビュアー — 保存前に自動整形して品質を均一化したい

## 4. 機能概要

- `MarkdownFormatterService`（新規）を `Sources/Services/` 以下に追加
  - 処理: 見出し前後の空行統一・末尾スペース除去・連続空行を最大2行に圧縮・コードブロックのフェンス統一
  - **コードブロック内は一切変更しない**（フェンスの範囲を先に検出してスキップ）
  - 入力: `String`（現在のエディタ全文）、出力: `String`（整形済みテキスト）、変更数: `Int`
- `AppViewModel` に `formatCurrentDocument()` メソッドを追加（NSTextView 全体をアンドゥ可能な形で置換）
- メニューバー「Format」→「Format Document」(⌘⇧F) で呼び出し
- 設定で「保存時に自動整形」トグル（`AppState` に `autoFormatOnSave: Bool` 追加）
- 整形変更数をステータスバーにトースト表示（例: "32 changes applied"）

## 5. スコープ

**M**: Service 新規 + AppViewModel 変更 + 設定追加 + テスト

## 6. 受け入れ条件

1. ⌘⇧F で Format Document が実行され、エディタ内容が整形される
2. コードブロック内部（``` で囲まれた範囲）は変更されない
3. 整形後、変更数がトーストまたはステータスバーに表示される
4. 設定「保存時に自動整形」が ON のとき、⌘S 保存前に自動で整形が走る
5. 整形操作は Undo（⌘Z）で元に戻せる
6. `swift build` が通る
7. `MarkdownFormatterService` のユニットテストが通る

## 7. 想定リスク

- フォーマッターが Markdown 意味を変える可能性 → コードブロック範囲を先に検出してスキップ
- autoFormatOnSave で Undo 履歴が複雑化 → NSTextView の undoManager 経由で適切に登録

## 8. 影響範囲マップ

### 変更対象ファイル（確定）

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `Sources/Services/MarkdownFormatterService.swift` | 新規追加 | フォーマットロジック本体 |
| `Sources/App/AppViewModel.swift` | 変更 | `formatCurrentDocument()` メソッド追加 |
| `Sources/App/AppCommand.swift` | 変更 | `formatDocument` コマンド追加 |
| `Sources/App/kobaamdApp.swift` | 変更 | メニューバーに Format Document (⌘⇧F) 追加 |
| `Sources/Services/AppState.swift` | 変更 | `autoFormatOnSave: Bool` プロパティ追加 |
| `Sources/Views/Settings/SettingsView.swift` | 変更 | 自動整形トグル追加 |
| `Sources/Views/MainWindowView.swift` | 変更 | formatDocument 通知リスナー追加・トースト表示 |
| `Tests/kobaamdTests/MarkdownFormatterServiceTests.swift` | 新規追加 | ユニットテスト |

### 変更してはいけない箇所

- `Sources/Views/Sidebar/SidebarView.swift` — サイドバー全体構造（他タブに影響）
- `Sources/Views/Sidebar/OutlineView.swift` — アウトラインタブ
- `Sources/Views/Sidebar/SearchView.swift` — 検索タブ
- `Sources/Views/Sidebar/FileTreeView.swift` — ファイルツリータブ
- `Sources/Services/MarkdownService.swift` — プレビュー用パーサー（フォーマッターとは別）
- `Sources/Views/Editor/NSTextViewWrapper.swift` — エディタコア（直接編集しない）
- `Sources/Views/Editor/EditorView.swift` — エディタ View（直接編集しない）
- `Sources/ViewModels/OutlineViewModel.swift` — アウトライン ViewModel
- `Sources/ViewModels/SearchViewModel.swift` — 検索 ViewModel

### 事後確認（実装後）

実際に変更したファイルは計画通り8ファイルで、想定外の変更はなかった。

- `MarkdownFormatterService.swift` — 新規作成済み
- `AppCommand.swift` — `formatDocument` ケース追加済み
- `AppViewModel.swift` — `formatCurrentDocument()` / トースト関連プロパティ追加済み
- `kobaamdApp.swift` — `CommandMenu("Format")` と `Notification.Name` エイリアス追加済み
- `AppState.swift` — `autoFormatOnSave` computed property 追加済み
- `SettingsView.swift` — "Formatting" セクション追加済み
- `MainWindowView.swift` — `ZStack` でトースト表示、通知リスナー追加済み
- `MarkdownFormatterServiceTests.swift` — 5テスト新規追加済み

ビルド: `swift build` pass
テスト: `swift test` exit 0

---

generated_by: kobaamd_implement_code (PRD-lite from issue description)
generated_at: 2026-04-25
