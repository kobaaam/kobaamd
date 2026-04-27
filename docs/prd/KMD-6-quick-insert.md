# KMD-6: クイックインサート — AI向けスニペット／テンプレート挿入コマンド

## 1. 背景・目的

kobaamdのビジョン「AIが生成したMarkdownを最も快適に扱えるエディタ」において、AIへの指示（プロンプト）をMarkdown内に書き込む操作が頻繁に発生する。現在は`{{プロンプト}}`記法を手入力するしかなく、よく使うパターン（「この節を箇条書きにして」「要約して」「英訳して」など）を毎回タイプするのは非効率。⌘K でフローティングパレットを表示し、AI指示テンプレートをキーボード1つで挿入できるようにする。

---

## 2. ターゲットユーザーとユースケース

### ペルソナ A — 日常的AIコラボレーター

毎日AIと共同でドキュメントを書くユーザー。定型プロンプトを素早く挿入したい。

**シナリオ**: 段落を書き終えた後 ⌘K → パレットが開く → 「箇条書き」を選択 → カーソル位置に`{{この段落を箇条書きに変換して}}`が挿入 → Enterで即実行。

### ペルソナ B — カスタムワークフロー利用者

独自のプロンプトテンプレートを設定して使いたいユーザー。SettingsViewでカスタムテンプレートを登録し、再利用する。

---

## 3. 機能要件

### 必須要件

* ⌘K でフローティングパレット `QuickInsertView`（SwiftUIオーバーレイ）を表示
* テンプレートリスト（デフォルト5件）をフィルタリング検索してEnterで挿入
* 挿入内容は `{{選択したプロンプトテキスト}}` 形式でカーソル位置に追記してパレットを閉じる
* デフォルトテンプレート: 「この段落を要約して」「箇条書きに変換して」「英語に翻訳して」「続きを3段落書いて」「見出し構造を提案して」
* Esc でパレットを閉じ、エディタのフォーカスを維持

### オプション要件

* `SettingsView` でカスタムテンプレートの追加・編集・削除（`UserDefaults` に永続化）

---

## 4. 非機能要件

* **パフォーマンス**: パレット表示は100ms以内。フィルタリングは入力ごとに即座に更新。
* **アクセシビリティ**: パレット内のリストはVoiceOver対応。キーボードのみで操作可能（↑↓でナビゲート、Enterで挿入、Escで閉じる）。
* **macOS整合性**: ⌘K が未使用であることを確認済み。SwiftUI `.overlay` を使用。

---

## 5. UI/UX

```
エディタ上に重なるフローティングパレット（⌘K でトグル）:

+--[ QuickInsertView ]-----------------------------+
|  [テンプレートを検索...                        ] |
+--------------------------------------------------+
|  ▶ この段落を要約して               ← 選択中   |
|    箇条書きに変換して                            |
|    英語に翻訳して                                |
|    続きを3段落書いて                             |
|    見出し構造を提案して                          |
+--------------------------------------------------+
|  Enter: 挿入  ↑↓: 選択  Esc: 閉じる             |
+--------------------------------------------------+
```

* `QuickInsertView.swift`（新規: `Sources/Views/Editor/QuickInsertView.swift`）
* パレットはエディタ中央上部に表示（Spotlightライクなオーバーレイ、幅 400pt）
* 検索フィールドに入力するとリストがリアルタイムフィルタリング（prefix match）
* Enterで選択テンプレートを `{{テンプレート内容}}` 形式でカーソル位置に挿入してパレットを閉じる

---

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] エディタにフォーカスがある状態で ⌘K を押すと、クイックインサートパレットが表示される
- [ ] パレットからテンプレートを選択してEnterを押すと、エディタのカーソル位置に `{{テンプレート内容}}` が挿入される
- [ ] パレットの検索フィールドに「要約」と入力すると「この段落を要約して」のみが表示される（リアルタイムフィルタリング）
- [ ] Esc キーを押すとパレットが閉じ、エディタのフォーカスが維持される
- [ ] SettingsView でカスタムテンプレートを追加すると、次回パレット表示時にリストに表示される

---

## 7. テスト戦略

### 単体テスト対象ファイル

* `Sources/Services/SnippetStore.swift`（新規）: テンプレートのCRUD・`UserDefaults` 永続化
  * テストケース: デフォルトテンプレートの読み込み・カスタム追加・削除・フィルタリング（空文字・一致・不一致）

---

## 8. 影響範囲マップ

### 変更対象ファイル

| ファイル | 種別 | 変更内容 |
|---|---|---|
| `Sources/Views/Editor/QuickInsertView.swift` | 追加 | フローティングパレットUI（SwiftUI overlay） |
| `Sources/Services/SnippetStore.swift` | 追加 | テンプレートCRUD + UserDefaults永続化 |
| `Sources/App/AppCommand.swift` | 変更 | `case quickInsert = "kobaamd.quickInsertRequested"` を追加 |
| `Sources/App/kobaamdApp.swift` | 変更 | ⌘K メニューコマンド追加・Notification.Name alias 追加 |
| `Sources/App/AppViewModel.swift` | 変更 | `SnippetStore` インスタンス保持・`showQuickInsert: Bool` フラグ追加・`insertSnippet(text:)` メソッド追加 |
| `Sources/Views/Editor/EditorView.swift` | 変更 | `quickInsertRequested` 受信・overlay で `QuickInsertView` 表示 |
| `Sources/Views/Editor/NSTextViewWrapper.swift` | 変更 | カーソル位置へのテキスト挿入メソッドを公開（AppViewModelからの呼び出し対応） |
| `Sources/Views/Settings/SettingsView.swift` | 変更 | カスタムテンプレート管理UIセクションを追加 |
| `Tests/kobaamdTests/SnippetStoreTests.swift` | 追加 | SnippetStore 単体テスト |

### 他機能への影響（同居コードの確認）

- `EditorView.swift` を変更するが、既存の FindReplaceBar・AIAssistPanel・自動保存・autoList 機能には触れない
- `NSTextViewWrapper.swift` を変更するが、スクロール比率追跡・行ハイライト・⌘Return AIインライン補完には触れない
- `AppCommand.swift` に case 追加のみ（既存 case への変更なし）
- `kobaamdApp.swift` に CommandGroup 追加のみ（既存コマンド変更なし）
- `AppViewModel.swift` に新プロパティ・メソッド追加のみ（既存ロジックへの変更なし）
- `SettingsView.swift` に Section 追加のみ（既存 AI キー設定・Formatting セクションへの変更なし）

### 変更してはいけない箇所

- `NSTextViewWrapper.swift`: スクロール購読ロジック（`subscribeScroll`）・行ハイライトロジック（`subscribeSelection`, `highlightCurrentLine`）・⌘Return AIインライン補完ロジック・自動リスト継続ロジック（`handleAutoListReturn`）
- `EditorView.swift`: FindReplaceBar 表示ロジック・AIAssistPanel 表示ロジック・自動保存ロジック（`scheduleAutoSave`）・ドロップハンドリング
- `AppViewModel.swift`: タブ管理ロジック全体（`openInTab`, `switchToTab`, `closeTab`, `flushActiveTab`, `activate`）・PDF エクスポートロジック・AI インライン補完ロジック（`startAIInlineCompletion`, `cancelAIGeneration`）
- `kobaamdApp.swift`: 既存の CommandGroup（NewItem, SaveItem, SaveItem-after, textEditing, Format, sidebar）の内容
- `AppCommand.swift`: 既存の case 定義（`save`, `newFile`, `find`, `openFolder`, `aiAssist`, `toggleSidebar`, `newTab`, `formatDocument`, `exportPDF`, `cancelAIGeneration`）
- `SettingsView.swift`: AI プロバイダーセクション・Formatting セクション・保存ボタン

---

## 9. 参考資料

* KMD-4（AIインライン補完ストリーミング対応）と組み合わせると効果大
* iA Writer: テンプレート機能
* Obsidian: Templaterプラグイン
* VS Code: Snippet挿入（⌃Space）
