# KMD-32: ディレクトリ単位 TODO 横断表示

> Linear: <https://linear.app/kobaan/issue/KMD-32/todoをディレクトリ単位で確認したい>

## 1. 背景・目的

kobaamd は「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」をビジョンとしている。現在の TODO パネル（サイドバー下部）は **編集中の単一ファイル** のみを対象としており、`TODO:` / `FIXME:` の検出範囲が狭い。

AI エージェントを用いた開発プロジェクトでは、複数の `.md` ファイルにまたがって TODO が散在することが一般的である（例: PRD・ADR・エージェント定義ファイルなど）。現状では各ファイルを逐一開かなければ TODO の全体像が把握できず、ワークスペース全体の作業漏れに気づきにくい。

本機能は TODO の検出スコープを **ワークスペース（Explorer）単位** および **ディレクトリ単位** に拡張し、横断的な TODO 管理を可能にする。

## 2. 「選択中のディレクトリ」の定義（前提）

> ⚠️ **用語の固定**: 本 PRD で **「選択中のディレクトリ」** と書いた場合は次の 1 通りの意味のみを指す。サイドバーの選択状態や編集中ファイルの親フォルダは指さない。

- **「選択中のディレクトリ」 ＝ ユーザーがアプリを開いて最初に開いたワークスペースフォルダ**
- 実装上は **`AppViewModel.fileTreeViewModel.folders.first?.url`**（`AppState.loadWorkspaceFolders().first` で復元される最初のルート）
- このフォルダは **アプリ起動時に Explorer の一番上に表示される** ディレクトリであり、ユーザーから見て「いま自分の作業対象のプロジェクトルート」と認識される
- このディレクトリはユーザーが Explorer に対して `addFolder` で別のフォルダを追加したり、削除したりしない限り変わらない
- **したがって Folder スコープの対象は、編集中ファイルやサイドバーで選択中のノードに追従して切り替わってはならない**

### 「選択中のディレクトリ」が空のケース

- ワークスペース未開設状態（`fileTreeViewModel.folders` が空）の場合、Folder スコープは「ワークスペースを開いてください」を促すプレースホルダーを表示する（TODO 0 件としてエラーにしない）

## 3. ターゲットユーザーとユースケース

- **ペルソナ A: AI エージェント開発者** — 20 以上の `.md` ファイルを 1 つのワークスペースで管理し、ワークスペース全体の TODO を一覧したい
- **ペルソナ B: テクニカルライター** — 自分のプロジェクトルート（最初に開いた `docs/` 等）配下だけの TODO を確認したい
- **ペルソナ C: 個人ブロガー** — 最初に開いた下書きフォルダ配下の TODO だけを確認したい

> 注: ペルソナ B / C のいずれも「**最初に開いたフォルダ**」が対象になる。Explorer に複数フォルダを追加していても、Folder スコープでは常に **最初の 1 つだけ** が対象。複数フォルダ全体を見たい場合は Workspace スコープを使う。

## 4. 機能要件

### 必須要件

- **R1**: TODO パネルに **スコープ切り替え** を導入する（File / Folder / Workspace の 3 値）
- **R2**: スコープが Folder / Workspace の場合、各 TODO アイテムに **ファイル名（相対パス）** を表示する
- **R3**: Folder / Workspace スコープの TODO アイテムをクリックすると、該当ファイルをタブで開き、該当行にジャンプする
- **R4**: スコープ切り替え時およびファイル保存時に TODO リストを自動更新する
- **R5**: Folder / Workspace スキャンはバックグラウンドスレッドで実行し、メインスレッドをブロックしない
- **R6**: **Folder スコープの対象は section 2 で定義した「選択中のディレクトリ」のみ**。編集中ファイル切替・サイドバー選択ノード変更で Folder スコープのスキャン対象は変わらない（§2 不変条件）
- **R7**: Explorer のワークスペースフォルダ追加 / 削除（`fileTreeViewModel.folders` の変動）に応じて、Folder スコープの対象（先頭フォルダ）が変わったら自動で再スキャンする

### オプション要件

- **O1**: ファイル単位でグルーピング表示（折り畳み可能なセクション）
- **O2**: TODO / FIXME のフィルタリング（ラベル別絞り込み）
- **O3**: TODO 件数をスコープ切り替えボタンのバッジとして表示
- **O4**: FSEvents によるリアルタイムファイル変更検知

## 5. 非機能要件

- **パフォーマンス**: Workspace スキャンは 1000 ファイル以下で 2 秒以内
- スキャン中はエディタ操作をブロックしない
- 大規模ディレクトリでは `maxDepth=5`（FileService.loadNodes と同一）を適用
- デバウンス（500ms）でディレクトリ選択高速切り替え時の無駄なスキャンを抑制
- スコープ切り替えコントロールに VoiceOver ラベルを付与
- セグメンテッドコントロールは macOS 標準の `Picker(.segmented)` を使用

## 6. UI/UX

### TODO パネル レイアウト

```
+------------------------------------------+
| [v] TODO (12)                            |  <- 既存ヘッダー（折り畳みトグル + 件数）
+------------------------------------------+
| [File] [Folder] [Workspace]              |  <- スコープ切り替え（Picker segmented）
+------------------------------------------+
|  docs/prd/KMD-30.md                      |  <- ファイルグループヘッダー
|  ┌────────────────────────────────────┐  |
|  │ TODO  L23  実装詳細を追記する       │  |
|  │ FIXME L45  パス解決の修正           │  |
|  └────────────────────────────────────┘  |
+------------------------------------------+
```

### SwiftUI ビュー構成

- **TodoScopePickerView**: `Picker(.segmented)` で File / Folder / Workspace 切替
- **TodoView（拡張）**: スコープが Folder/Workspace の場合はファイル名ヘッダー付きグループ表示
- **TodoGroupHeaderView**: 相対パスを表示する小さなヘッダー（`system(size: 10, weight: .medium, design: .monospaced)`、`Color.kobaMute`）

### スコープ切り替えの挙動

- **File**: 編集中テキストが変わるたびに 300ms デバウンス（現行動作）
- **Folder**: **`fileTreeViewModel.folders.first?.url`（§2 で定義した「選択中のディレクトリ」）配下を 500ms デバウンスでスキャン**。Explorer の最初のルートが空 / 未設定の場合は「ワークスペースを開いてください」プレースホルダーを表示
- **Workspace**: `fileTreeViewModel.folders` 全体を 500ms デバウンスでスキャン

### アクセシビリティ表記

- Folder ボタンの `accessibilityHint`: 「最初に開いたフォルダ配下の TODO を表示」
- スコープピッカー全体の `accessibilityLabel`: 「TODO 表示スコープ」（既存維持）

## 7. 受け入れ条件

- [ ] **AC1**: TODO パネルのヘッダー直下にスコープ切り替えセグメンテッドコントロールが表示され、タップで切り替わる
- [ ] **AC2**: Workspace スコープに切り替えると、Explorer で開いている全フォルダ内の `.md` ファイルから TODO/FIXME がファイル名付きで一覧表示される
- [ ] **AC3**: Folder スコープに切り替えると、**`fileTreeViewModel.folders.first?.url`（最初に開いたワークスペースフォルダ）配下** の `.md` ファイルのみの TODO/FIXME が表示される。**編集中ファイルの親ディレクトリやサイドバーの選択ノードに左右されない**
- [ ] **AC4**: Folder スコープ表示中に **別のファイルを開いても**（`openInTab`）TODO 一覧の対象ディレクトリは変わらない（最初のフォルダのまま）
- [ ] **AC5**: Folder / Workspace スコープの TODO アイテムをクリックすると、該当ファイルが新しいタブで開き、該当行にカーソルがジャンプする
- [ ] **AC6**: 100 個の `.md` ファイルを含むワークスペースで Workspace スコープに切り替えた際、TODO 一覧が 2 秒以内に表示される
- [ ] **AC7**: スキャン中にエディタの入力操作がブロックされない
- [ ] **AC8**: File スコープでは従来通り編集中ファイルのみの TODO が表示される（既存動作のリグレッションなし）
- [ ] **AC9**: Explorer に新しいフォルダを追加すると、それが先頭になった場合のみ Folder スコープの対象が更新される（複数フォルダ運用時の整合性）
- [ ] **AC10**: ワークスペース未開設状態で Folder スコープを選んでも空表示になりクラッシュしない

## 8. テスト戦略

### 単体テスト（Tests/kobaamdTests/TodoViewModelTests.swift を更新）

| 対象 | テスト内容 |
| -- | -- |
| `TodoViewModel.parseTodos(from:)` | 既存の File スコープ動作（リグレッション防止） |
| `TodoViewModel.scanDirectory(at:)` | 指定ディレクトリ配下 `.md` から TODO 収集 |
| `TodoViewModel.scanWorkspace(folders:)` | 複数フォルダ横断 |
| スコープ切り替え | アイテムの正しいリセット・再ロード |
| `maxDepth=5` 制限 | 過度に深い階層がスキップされること |
| **Folder スコープ不変条件**（新規） | `setScope(.folder)` 後に `updateFolderRoot(A)` した状態で、ファイル選択を模した経路（編集中ファイルの親が `B` になっても）で `folderRoot` が `A` のまま維持されること |
| **Folder ルート更新の追従**（新規） | `updateWorkspaceRoots([A,B])` で先頭が `A` のとき Folder root が `A`、`updateWorkspaceRoots([C,A,B])` に更新後は `C` に切り替わること |

## 9. 影響範囲マップ

### 変更ファイル

| ファイル | 変更種別 | 備考 |
| -- | -- | -- |
| `Sources/ViewModels/TodoViewModel.swift` | 変更 | スコープ管理（File/Folder/Workspace）、ディレクトリスキャン、`TodoItem.fileURL` 維持。**`updateFolderRoot` のセマンティクスを「最初のワークスペースフォルダ」に変更**。既存の `update(text:)` / `parseTodos(from:)` ロジックは維持 |
| `Sources/Views/Sidebar/TodoView.swift` | 変更 | スコープ切替 Picker、ファイルグループヘッダー、`accessibilityHint` 文言更新 |
| `Sources/Views/Sidebar/SidebarView.swift` | 軽微変更 | TODO セクションの高さ計算をピッカー分（28px）追加考慮 |
| `Sources/App/AppViewModel.swift` | 変更 | **`openInTab` / `activate` から `todoViewModel.updateFolderRoot(url.deletingLastPathComponent())` 呼び出しを撤去**。`refreshQuickOpenIndex` で `updateFolderRoot(folders.first?.url)` を伝達するよう変更（Workspace 更新と同タイミング） |
| `Tests/kobaamdTests/TodoViewModelTests.swift` | 変更 | Folder 不変条件テスト + Folder ルート追従テストを追加 |
| `docs/prd/KMD-32-todo-directory-scope.md` | 変更 | 本 PRD の §2 / §6 / §7 / §9 を改訂（人間フィードバック反映） |

### 変更してはいけない箇所（不変条件）

- **`Sources/Services/FileService.swift`**: 既存の `readFile(at:)` / `loadNodes(at:)` をそのまま利用する（変更しない）
- **`Sources/Views/Sidebar/SidebarView.swift` の EXPLORER / OUTLINE セクション**: TODO セクションの高さ変更が OUTLINE の高さ計算に波及しないこと。`outlinePanelRatio` のセマンティクスは維持
- **`Sources/Views/Sidebar/OutlineView.swift`**: 触らない（`.jumpToLine` 通知の受発信パターンを共有するのみ）
- **`Sources/Views/Sidebar/FileTreeView.swift` / `SearchView.swift`**: 触らない
- **`Sources/App/kobaamdApp.swift` の `Notification.Name.jumpToLine` 定義**: 既存定義をそのまま再利用（再定義禁止）
- **`TodoViewModel.parseTodos(from:)`**: シグネチャ・既存挙動を維持
- **`TodoViewModel.update(text:)`**: 既存の File スコープ動作（300ms デバウンス）を維持
- **§2 で定義した「選択中のディレクトリ」のセマンティクス**: 実装は §2 の単一定義から外れてはならない。「編集中タブ url の親」「サイドバー選択ノードの親」など別解釈を実装に紛れ込ませない

### 共有コンテナへの注意

- `SidebarView.swift` は EXPLORER / OUTLINE / TODO の 3 セクションが同居する
- `AppViewModel.swift` は中心的ファイル。変更は `todoViewModel` 関連の最小限に留める

## 10. 参考資料

- VS Code TODO Highlight 拡張
- Apple Documentation — `Picker(.segmented)` / `TaskGroup`
- 既存実装: `Sources/ViewModels/SearchViewModel.swift`（ワークスペース横断走査の参考）
