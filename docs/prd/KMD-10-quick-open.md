---
linear: KMD-10
status: in-progress
created_at: 2026-04-27
author: kobaamd_implement_code
---

# Quick Open (⌘P) — ファイル名インクリメンタル検索

## 1. 背景・目的

kobaamd のビジョン「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」において、ファイル間の高速移動はキーボード中心ワークフローの要である。現在のファイルアクセス手段はサイドバーのクリックと全文検索（⌘F）のみで、ファイル名による瞬時のジャンプ手段がない。VS Code / Xcode / Obsidian が標準装備する「⌘P で開くファイル名インクリメンタル検索」は、Mac ネイティブエディタとして当然期待されるショートカット体験であり、その不在が kobaamd のキーボードファースト感を損なっている。

## 2. ターゲットユーザーとユースケース

**ペルソナ A — マルチファイル管理者**: AI に複数のドキュメントを並行生成させ、ディレクトリに格納している。サイドバーをスクロールしてファイルを探す時間を排除し、ファイル名の一部を打つだけで目的のファイルにジャンプしたい。

**ペルソナ B — キーボード至上主義者**: トラックパッドを触らずに全操作をこなしたい。⌘P → 2〜3文字入力 → Enter でファイルを開く操作が自然に期待される。

## 3. 機能要件

- 必須要件:
  - ⌘P でフローティングオーバーレイを表示する（MainWindowView 内 `.sheet` または `.overlay` 実装）
  - テキストフィールドが自動フォーカスされ、即入力可能
  - FileTreeViewModel.folders 内の全ファイルノードをフラット化してインデックスとして使用（ディレクトリは除外）
  - 入力文字列で fuzzy/contains マッチ（大文字小文字無視）してリアルタイムフィルタリング
  - 候補一覧は最大 20 件表示。ファイル名 + 相対パスを表示
  - ↑↓ キーで候補選択、Enter でファイルを開く（AppViewModel.openInTab を呼ぶ）
  - ESC でパネルを閉じる
  - 候補クリックでもファイルを開く
  - AppCommand / Notification.Name に `quickOpen` を追加
  - kobaamdApp.swift の Commands に Quick Open メニュー項目（⌘P）を追加

- オプション要件:
  - 最近開いたファイルを優先ランキング表示（AppState.loadRecentFiles() 利用）
  - ファイルパスのハイライト（マッチ文字を強調）

## 4. 非機能要件

- パフォーマンス: ファイルツリーのフラット化は最大数百件程度を想定。フィルタは同期で十分
- アクセシビリティ: VoiceOver で候補リストが読み上げられること
- macOS との整合性: ⌘P はデフォルトで「ページ設定」だが、アプリ内フォーカス時にオーバーライドすることで対処

## 5. UI/UX

```
+------------------------------------------+
|  [ Search files...                      ] |  <- TextField、自動フォーカス
+------------------------------------------+
|  doc.text  README.md         /docs/       |  <- 候補行（ファイル名 + パス）
|> doc.text  design.md         /docs/       |  <- 選択中（ハイライト）
|  doc.text  notes.md          /            |
+------------------------------------------+
```

- パネルは画面中央上部に配置（MainWindowView のオーバーレイ）
- 背景はぼかしマテリアル（`.regularMaterial`）、角丸 12pt
- 幅 480pt 固定、最大高さ 360pt（スクロール可）

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] ⌘P でパネルが開き、テキストフィールドにフォーカスが当たる
- [ ] ファイル名の一部を入力すると候補が絞り込まれる（大文字小文字無視）
- [ ] Enter キーまたはクリックでファイルが新しいタブで開く
- [ ] ESC でパネルが閉じる
- [ ] ↑↓ キーで候補を選択できる
- [ ] ワークスペースにフォルダが追加されていない場合、空状態メッセージを表示する
- [ ] swift build が通る

## 7. テスト戦略

- 単体テスト: QuickOpenViewModel のフィルタリングロジック（contains マッチ、大文字小文字無視、最大件数）
- 手動確認: ⌘P でパネル開閉、ファイル名入力・選択・開封フロー

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/ViewModels/QuickOpenViewModel.swift` | 追加 | 新規 ViewModel |
| `Sources/Views/QuickOpen/QuickOpenView.swift` | 追加 | パネル UI |
| `Sources/App/AppCommand.swift` | 変更 | `quickOpen` case 追加 |
| `Sources/App/kobaamdApp.swift` | 変更 | ⌘P コマンド登録、Notification.Name 追加 |
| `Sources/Views/MainWindowView.swift` | 変更 | overlay でパネルを表示、notification 受信 |
| `Sources/App/AppViewModel.swift` | 変更 | `showQuickOpen: Bool` プロパティ追加 |

**共有コンテナへの注意**（複数機能が同居するファイルを変更する場合は必ず記載）:
- `AppCommand.swift` には save / newFile / find / openFolder / aiAssist / toggleSidebar / newTab / formatDocument / exportPDF が定義されている。追記のみ行い既存 case を変更しない
- `kobaamdApp.swift` には Commands / Notification.Name / AppDelegate が定義されている。Commands 拡張のみ追加し AppDelegate は変更しない
- `MainWindowView.swift` には DnD オーバーレイ・StatusCommandBar・ToolbarItems が実装されている。overlay の追加のみ行い既存 layout を変更しない
- `AppViewModel.swift` には tabs / save / AI inline などが実装されている。`showQuickOpen` プロパティの追加のみ行い既存メソッドを変更しない

**変更してはいけない箇所**:
- `FileTreeViewModel.swift` — 変更不要。フォルダ・ノードデータの読み取りのみ
- `SidebarView.swift` — 変更不要
- `FileTreeView.swift` — 変更不要
- `SearchView.swift` / `SearchViewModel.swift` — 変更不要（参考にするだけ）
- `EditorView.swift` / `NSTextViewWrapper.swift` — 変更不要
- `TabBarView.swift` — 変更不要
- AppDelegate のウィンドウフレーム保存・復元ロジック — 変更不要
- 既存 Notification.Name の値文字列 — 変更不要（追加のみ）
- 既存 AppCommand の case — 変更不要（追加のみ）

### その他リスク

- ⌘P は macOS デフォルトで「ページ設定」。`CommandGroup(replacing: .printItem)` または独自 `CommandMenu` で上書き
- fuzzy match は外部ライブラリ不要。`localizedCaseInsensitiveContains` で十分
- 既存テスト（QuickOpenViewModel テスト以外）は変更なし

## 9. 計測・成果指標

- ユーザーが ⌘P を押してファイルを開くまでの操作数: 目標 3 アクション以内（⌘P → 入力 → Enter）

## 10. 参考資料

- VS Code: ⌘P でファイル名検索、最近使ったファイル優先表示
- Obsidian: Quick Switcher（⌘O）でファイル横断移動
- Xcode: Open Quickly (⇧⌘O) が同機能を提供
- KMD-6（クイックインサート）— 「クイック」系 UI の一貫性を統一する視点で参照
