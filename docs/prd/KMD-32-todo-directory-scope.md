# KMD-32: ディレクトリ単位 TODO 横断表示

> Linear: <https://linear.app/kobaan/issue/KMD-32/todoをディレクトリ単位で確認したい>

## 1. 背景・目的

kobaamd は「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」をビジョンとしている。現在の TODO パネル（サイドバー下部）は **編集中の単一ファイル** のみを対象としており、`TODO:` / `FIXME:` の検出範囲が狭い。

AI エージェントを用いた開発プロジェクトでは、複数の `.md` ファイルにまたがって TODO が散在することが一般的である（例: PRD・ADR・エージェント定義ファイルなど）。現状では各ファイルを逐一開かなければ TODO の全体像が把握できず、ワークスペース全体の作業漏れに気づきにくい。

本機能は TODO の検出スコープを **ワークスペース（Explorer）単位** および **ディレクトリ単位** に拡張し、横断的な TODO 管理を可能にする。

## 2. ターゲットユーザーとユースケース

- **ペルソナ A: AI エージェント開発者** — 20 以上の `.md` ファイルを 1 つのワークスペースで管理し、ワークスペース全体の TODO を一覧したい
- **ペルソナ B: テクニカルライター** — 特定ディレクトリ（`docs/api/` 等）だけの TODO を確認したい
- **ペルソナ C: 個人ブロガー** — 下書きフォルダ（`drafts/`）内の TODO だけを確認したい

## 3. 機能要件

### 必須要件

- **R1**: TODO パネルに **スコープ切り替え** を導入する（File / Folder / Workspace）
- **R2**: スコープが Folder / Workspace の場合、各 TODO アイテムに **ファイル名（相対パス）** を表示する
- **R3**: Folder / Workspace スコープの TODO アイテムをクリックすると、該当ファイルをタブで開き、該当行にジャンプする
- **R4**: スコープ切り替え時およびファイル保存時に TODO リストを自動更新する
- **R5**: Folder / Workspace スキャンはバックグラウンドスレッドで実行し、メインスレッドをブロックしない

### オプション要件

- **O1**: ファイル単位でグルーピング表示（折り畳み可能なセクション）
- **O2**: TODO / FIXME のフィルタリング（ラベル別絞り込み）
- **O3**: TODO 件数をスコープ切り替えボタンのバッジとして表示
- **O4**: FSEvents によるリアルタイムファイル変更検知

## 4. 非機能要件

- **パフォーマンス**: Workspace スキャンは 1000 ファイル以下で 2 秒以内
- スキャン中はエディタ操作をブロックしない
- 大規模ディレクトリでは `maxDepth=5`（FileService.loadNodes と同一）を適用
- デバウンス（500ms）でディレクトリ選択高速切り替え時の無駄なスキャンを抑制
- スコープ切り替えコントロールに VoiceOver ラベルを付与
- セグメンテッドコントロールは macOS 標準の `Picker(.segmented)` を使用

## 5. UI/UX

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
- **Folder**: `fileTreeViewModel.selectedNode` の親ディレクトリ配下を 500ms デバウンスでスキャン
- **Workspace**: `fileTreeViewModel.folders` 全体を 500ms デバウンスでスキャン

## 6. 受け入れ条件

- [ ] TODO パネルのヘッダー直下にスコープ切り替えセグメンテッドコントロールが表示され、タップで切り替わる
- [ ] Workspace スコープに切り替えると、Explorer で開いている全フォルダ内の `.md` ファイルから TODO/FIXME がファイル名付きで一覧表示される
- [ ] Folder スコープに切り替えると、サイドバーで選択中のディレクトリ配下の `.md` ファイルのみの TODO/FIXME が表示される
- [ ] Folder / Workspace スコープの TODO アイテムをクリックすると、該当ファイルが新しいタブで開き、該当行にカーソルがジャンプする
- [ ] 100 個の `.md` ファイルを含むワークスペースで Workspace スコープに切り替えた際、TODO 一覧が 2 秒以内に表示される
- [ ] スキャン中にエディタの入力操作がブロックされない
- [ ] File スコープでは従来通り編集中ファイルのみの TODO が表示される（既存動作のリグレッションなし）

## 7. テスト戦略

### 単体テスト（Tests/kobaamdTests/TodoViewModelTests.swift を新規作成）

| 対象 | テスト内容 |
| -- | -- |
| `TodoViewModel.parseTodos(from:)` | 既存の File スコープ動作（リグレッション防止） |
| `TodoViewModel.scanDirectory(at:)` | 指定ディレクトリ配下 `.md` から TODO 収集 |
| `TodoViewModel.scanWorkspace(folders:)` | 複数フォルダ横断 |
| スコープ切り替え | アイテムの正しいリセット・再ロード |
| `maxDepth=5` 制限 | 過度に深い階層がスキップされること |

## 8. 影響範囲マップ

### 変更ファイル

| ファイル | 変更種別 | 備考 |
| -- | -- | -- |
| `Sources/ViewModels/TodoViewModel.swift` | 変更 | スコープ管理（File/Folder/Workspace）、ディレクトリスキャン、`TodoItem.fileURL` 追加。既存の `update(text:)` / `parseTodos(from:)` ロジックは維持 |
| `Sources/Views/Sidebar/TodoView.swift` | 変更 | スコープ切替 Picker 追加、ファイルグループヘッダー対応、クリック時の openInTab → jumpToLine |
| `Sources/Views/Sidebar/SidebarView.swift` | 軽微変更 | TODO セクションの高さ計算をピッカー分（28px）追加考慮 |
| `Sources/App/AppViewModel.swift` | 軽微変更 | `todoViewModel` へのスコープ伝達（選択中ディレクトリ・ワークスペースフォルダ一覧）。既存ロジックは維持 |
| `Tests/kobaamdTests/TodoViewModelTests.swift` | 新規 | 単体テスト |
| `docs/prd/KMD-32-todo-directory-scope.md` | 新規 | 本 PRD |

### 変更してはいけない箇所（不変条件）

- **`Sources/Services/FileService.swift`**: 既存の `readFile(at:)` / `loadNodes(at:)` をそのまま利用する（変更しない）
- **`Sources/Views/Sidebar/SidebarView.swift` の EXPLORER / OUTLINE セクション**: TODO セクションの高さ変更が OUTLINE の高さ計算に波及しないこと。`outlinePanelRatio` のセマンティクスは維持
- **`Sources/Views/Sidebar/OutlineView.swift`**: 触らない（`.jumpToLine` 通知の受発信パターンを共有するのみ）
- **`Sources/Views/Sidebar/FileTreeView.swift` / `SearchView.swift`**: 触らない
- **`Sources/App/kobaamdApp.swift` の `Notification.Name.jumpToLine` 定義**: 既存定義をそのまま再利用（再定義禁止）
- **`TodoViewModel.parseTodos(from:)`**: シグネチャ・既存挙動を維持。新しいスキャンは別メソッドとして追加
- **`TodoViewModel.update(text:)`**: 既存の File スコープ動作（300ms デバウンス）を維持

### 共有コンテナへの注意

- `SidebarView.swift` は EXPLORER / OUTLINE / TODO の 3 セクションが同居する
- `AppViewModel.swift` は中心的ファイル。変更は `todoViewModel` 関連の最小限に留める

## 9. 参考資料

- VS Code TODO Highlight 拡張
- Apple Documentation — `Picker(.segmented)` / `TaskGroup`
- 既存実装: `Sources/ViewModels/SearchViewModel.swift`（ワークスペース横断走査の参考）
