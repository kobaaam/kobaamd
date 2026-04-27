---
linear: KMD-7
status: in-progress
created_at: 2026-04-25
author: kobaamd_implement_code
---

# TODO 管理（ファイル内インラインコメント＋TODOリスト）

## 1. 背景・目的

kobaamd のビジョンは「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」であり、長文ドキュメントの作成・編集が主要ユースケースとなる。ドキュメント執筆中は「この部分はあとで書く」「確認が必要」といった保留メモが頻繁に発生するが、現状の kobaamd にはそれらを追跡する仕組みが存在しない。

ユーザーは `<!-- TODO: ... -->` や `TODO:` プレフィックスといったインライン記法を使って保留事項をファイルに記載するが、複数ファイルにわたる保留を一覧で確認する手段がなく、「どのファイルのどこに書いたか」を探す作業が別途発生してしまう。

本機能は、ファイル内の特定記法で記述した TODO コメントを横断的に収集・表示するパネルを提供することで、執筆の流れを止めずに保留管理を完結させる。Phase 4 ロードマップ（アウトライン・PDF Export）の一環として位置付ける。

## 2. ターゲットユーザーとユースケース

- 長文 Markdown ドキュメントを執筆するライター / 開発者
- AI が生成したドキュメントにレビューコメントを残す編集者
- 複数ファイルにまたがるプロジェクトで保留事項を管理したいユーザー

典型的なユースケース:
1. 執筆中に `TODO: 後でリンクを確認する` と書いておく
2. サイドバーの TODO タブに切り替えて未完了事項の全体像を確認する
3. 一覧のアイテムをクリックして該当行にジャンプし、内容を処理する

## 3. 機能要件

### 必須要件
- 現在開いているファイル（アクティブタブ）の `editorText` から TODO を収集・表示する
- 対応する記法:
  - `TODO: テキスト`（行頭または空白後）
  - `FIXME: テキスト`
  - `<!-- TODO: テキスト -->`
  - `<!-- FIXME: テキスト -->`
- サイドバーに「TODO」タブを追加し、`TodoView` を表示する
- 各アイテムに行番号を表示し、クリックで該当行にジャンプする（既存の `.jumpToLine` Notification を使用）
- editorText の変化を 300ms デバウンスして TODO を再収集する（OutlineViewModel と同パターン）

### オプション要件
- TODO / FIXME のラベル表示（種別バッジ）
- 件数バッジをタブに表示する

## 4. 非機能要件

- パフォーマンス: 300ms デバウンス、バックグラウンドスレッドでパース（OutlineViewModel と同方式）
- アクセシビリティ: `accessibilityLabel` を各行に付与
- macOS との整合性: SidebarView の既存タブ UI スタイルを踏襲する

## 5. UI/UX

```
+--SidebarView-----------------------+
| Files | Search | Outline | TODO(3) |
+------------------------------------+
| TODO  L12  後でリンクを確認する      |
| FIXME L34  エラーハンドリング見直し   |
| TODO  L87  図を追加する             |
+------------------------------------+
```

- タブヘッダーは既存の `Files` / `Search` / `Outline` と同じスタイル
- 各行: `[TODO|FIXME]` ラベル + 行番号 + テキスト
- 空状態: 「TODO が見つかりません」テキスト

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] サイドバーに "TODO" タブが表示される
- [ ] `TODO:` および `FIXME:` の両記法（プレーンテキスト・HTMLコメント）を検出できる
- [ ] 各アイテムに行番号が表示される
- [ ] アイテムクリックで該当行にジャンプする
- [ ] editorText が変更されると一覧が更新される（デバウンス 300ms）
- [ ] swift build が通る
- [ ] 既存テストが壊れない

## 7. テスト戦略

- 単体テスト: `TodoViewModel` のパースロジック（各記法パターン）
- 手動確認: `TODO:`/`FIXME:` を含む Markdown ファイルを開いてタブに表示されることを確認

## 8. 想定リスク・依存

### 影響範囲マップ（実装後確定版）

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/ViewModels/TodoViewModel.swift` | 追加 | OutlineViewModel に倣った @Observable クラス |
| `Sources/Views/Sidebar/TodoView.swift` | 追加 | OutlineView に倣ったリスト表示 |
| `Sources/Views/Sidebar/SidebarView.swift` | 変更 | `.todo` タブを enum と switch に追加、help テキストを三項演算子チェーンに変更 |
| `Sources/App/AppViewModel.swift` | 変更 | `todoViewModel` プロパティ追加、`markSaved()` と `updateEditorText()` に `todoViewModel.update()` 呼び出し追加 |

**実装後確認: 想定外のファイルへの変更はなし。**

SidebarView には現時点で Outline タブが存在しないことを実装前に確認。PRD では Outline タブが「Files / Search / Outline」の3タブと記載していたが、実際のコードは「Files / Search」の2タブだった。TODO タブを追加して3タブ構成とした。この差異は PRD 作成時の誤認であり、実装に影響なし。

**共有コンテナへの注意:**

- `SidebarView.swift` には `Files` / `Search` / `Outline` タブが同居する。`SidebarTab` enum に `.todo` を追加するのみで、他タブの表示ロジックには一切触れない
- `AppViewModel.swift` の既存プロパティ（tabs, editorText, isDirty, saveCurrentFile 等）は変更しない。`todoViewModel` プロパティの追加と `updateEditorText` / `markSaved` での `todoViewModel.update()` 呼び出しのみ行う

- 対象ファイルを使っている他機能:
  - SidebarView: Files タブ（FileTreeView）, Search タブ（SearchView）, Outline タブ（OutlineView）
  - AppViewModel: MainWindowView, EditorView, TabBarView, WYSIWYGEditorView など多数

- 変更してはいけない箇所:
  - SidebarView の `Files` / `Search` / `Outline` タブの UI・ロジック
  - AppViewModel の既存メソッド（openInTab, newTab, switchToTab, closeTab, saveCurrentFile, markSaved, markEdited 等）のシグネチャや挙動
  - OutlineViewModel / OutlineView
  - その他の既存 .swift ファイル（EditorView, TabBarView, MainWindowView など）

### その他リスク

- 既存コードへの影響: AppViewModel への `todoViewModel.update()` 追加は最小限
- 互換性: macOS 14 以降の API のみ使用（既存と同じ制約）
- 外部依存: なし

## 9. 計測・成果指標

- ユーザーが TODO 管理のためにエディタ外ツールを使う機会が減る

## 10. 参考資料

- OutlineViewModel / OutlineView — パターンのベースライン
- Notification.Name.jumpToLine — 行ジャンプ既存実装
