```yaml
linear: KMD-23
status: in-progress
created_at: 2026-04-28
author: kobaamd_create_prd
```

# 左サイドバーの構成リニューアル

## 1. 背景・目的

kobaamd のビジョンは「AIが生成したMarkdownを、Macで最も快適に扱えるエディタ」である。現在の左サイドバー (`SidebarView.swift`) は「Files / Search / TODO」の3タブをフラットに並べる構成になっている。この設計を VS Code 風の「ファイルツリー + アウトライン常時表示 + TODO 折り畳み」構成にリニューアルする。

## 2. ターゲットユーザーとユースケース

- AIライター: アウトラインで全体構造を把握しながらエディタで節を修正する
- テクニカルライター: ファイルツリーで素早くファイルを切り替えながら、現在のファイルのアウトラインを確認したい
- 個人ノートユーザー: 全文検索でメモを横断検索する

## 3. 機能要件

### 必須要件

1. ファイルエクスプローラーとアウトラインを同一サイドバーに共存させる
   - 上部: ファイルツリー（FileTreeView）を常時表示
   - 下部: アウトライン（OutlineView）を常時表示
   - 両者の境界はドラッグ可能なリサイズハンドルで分割
   - アウトラインが空の場合は最小高さに折り畳む
2. TODO パネルを左下固定エリアに移動する
   - サイドバー最下部に折り畳み可能なエリアとして配置
   - デフォルト: 折り畳み済み（ヘッダーのみ表示）
   - ヘッダーをクリックで展開/折り畳みをトグル
3. 検索をサイドバータブから削除する
   - SearchView は SidebarView から除去
   - ワークスペース横断検索は既存の検索経路を使う
4. SidebarTab enum を削除し、タブバー自体を撤去する

### オプション要件

1. アウトラインの折り畳みサイズを永続化する
2. TODO ヘッダーに件数バッジを表示する

## 6. 受け入れ条件

- [ ] サイドバーにタブバーが存在せず、上半分にファイルツリー・下半分にアウトラインが表示される
- [ ] アウトラインパネルに H1-H6 見出しがリスト表示され、クリックでエディタがその行にジャンプする
- [ ] リサイズハンドルをドラッグすると、両パネルの高さ比率がリアルタイムに変化する
- [ ] TODO ヘッダーをクリックすると TodoView が展開・折り畳みできる
- [ ] swift build がエラーなしで通過する
- [ ] アウトラインが空のとき「見出しが見つかりません」と表示され最小高さに自動縮小する

## 8. 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
| -- | -- | -- |
| `Sources/Views/Sidebar/SidebarView.swift` | 変更（大） | SidebarTab enum 削除、VStack ベースの新レイアウトに全面書き換え |
| `Sources/Views/Sidebar/OutlineView.swift` | 変更なし | SidebarView から直接参照されるだけで内部変更不要 |
| `Sources/Views/Sidebar/TodoView.swift` | 変更なし | SidebarView から直接参照されるだけで内部変更不要 |
| `Sources/Views/Sidebar/SearchView.swift` | 変更なし | SidebarView からの参照を除去するだけ。SearchView 自体は削除しない（将来別UIで使用可能） |
| `Sources/Views/MainWindowView.swift` | 変更なし | SidebarView() の呼び出しはそのまま |
| `Sources/App/AppViewModel.swift` | 変更なし | outlineViewModel / todoViewModel のプロパティはそのまま |

### 変更してはいけない箇所

- `SidebarView.swift` 内の `onAppear` ブロック（`fileTreeViewModel.restoreWorkspace()` と前回ファイル復元ロジック）
- `SidebarView.swift` 内の `onReceive(.openRecentNotification)` と `onReceive(NSApplication.didBecomeActiveNotification)` のリロードロジック
- `SidebarView.swift` 内の `openRecent(_:)` メソッド
- `SidebarView.swift` 内の `filePanel` computed property（ファイルツリーの empty state + FileTreeView 表示ロジック）
- `OutlineView.swift` の内部実装（outlineRow, ジャンプロジック）
- `TodoView.swift` の内部実装（todoRow, ジャンプロジック）
- `SearchView.swift` の内部実装
- `MainWindowView.swift` 全体
- `AppViewModel.swift` 全体
- `EditorView.swift` の outlineViewModel.update 呼び出し
