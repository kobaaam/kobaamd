---
title: ファイルツリーとアウトラインの同期
category: components
tags: [file-tree, outline, sidebar, navigation, scroll-sync]
sources: []
created: 2026-04-30
updated: 2026-04-30
---

# ファイルツリーとアウトラインの同期

## Summary

サイドバーはファイルツリー（ワークスペース内のファイル階層）とアウトライン（現在のドキュメントの見出し一覧）を縦分割で表示する。ファイル選択がエディタのテキストを更新し、テキスト変更がアウトラインを再構築し、アウトライン項目のクリックがエディタのスクロール位置を制御する――という単方向データフローで同期を実現している。

## Content

### FileTreeViewModel のディレクトリ走査と展開状態管理

`FileTreeViewModel` はマルチルートワークスペースを `[WorkspaceFolder]` で管理する。各 `WorkspaceFolder` はルート URL と、再帰的に構築された `[FileNode]` ツリーを保持する。

ディレクトリ走査は `FileService.loadNodes(at:)` が担当する。内部の `children(of:depth:maxDepth:)` メソッドが `FileManager.contentsOfDirectory` で子要素を列挙し、以下のルールで `FileNode` ツリーを構築する:

- **最大深度制限**: `maxDepth = 5` で無限再帰を防止
- **隠しファイル除外**: `.skipsHiddenFiles` オプションで `.git` 等を除外
- **拡張子フィルタ**: `FileService.supportedExtensions`（md, swift, json, yaml 等）に含まれるファイルのみ表示
- **ソート順**: ディレクトリが先、ファイルが後（アルファベット順）

走査は `Task.detached(priority: .userInitiated)` でバックグラウンド実行され、結果を `MainActor.run` で UI に反映する。アプリがフォアグラウンドに戻ったときは `NSApplication.didBecomeActiveNotification` を受けて 1 秒のデバウンス後に自動リロードする。

ワークスペース状態（フォルダ URL のリスト）は `AppState.saveWorkspaceFolders` / `loadWorkspaceFolders` で永続化され、起動時に `restoreWorkspace()` で復元される。

### FileNode の ID 安定化（URL-based）

```swift
struct FileNode: Identifiable, Hashable {
    var id: URL { url }
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [FileNode]?
}
```

`id` を `URL` にする設計判断が重要。`UUID()` を使うとリロードのたびに ID が変わり、SwiftUI の `OutlineGroup` が展開状態を失う。`URL` ベースの ID により、ツリー再構築後もユーザーが展開したフォルダはそのまま開いた状態を維持できる。

### OutlineViewModel の見出し抽出

`OutlineViewModel` はエディタテキストから Markdown 見出し（`# ` ~ `###### `）を抽出する。

**抽出ロジック** (`parseHeadings`):
1. テキストを行分割
2. `#` で始まる行を検出
3. `#` の連続数でレベル（1-6）を判定
4. `#` の直後にスペースがあることを検証（`##text` のような誤検知を防止）
5. `OutlineItem(level:text:line:)` を生成（`line` は 1-origin）

**デバウンス**: `update(text:)` は 300ms のデバウンスを適用。高速タイピング中の不要な再計算を抑制する。内部では `Task.sleep` + `Task.isCancelled` チェックによるキャンセル可能なデバウンスパターンを使用している。

**パース実行**: `Task.detached(priority: .userInitiated)` でバックグラウンドスレッドで実行し、結果を `MainActor.run` で反映。大きなドキュメントでも UI スレッドをブロックしない。

> **Note**: 現在は正規表現ベースの自前パーサーだが、Phase 4 で TreeSitter への移行を予定。swift-markdown の `Visitor` パターンは Markdown パーサーとしては使用しておらず、行番号ベースの軽量パースを採用している。

### サイドバータブの構成

`SidebarView` は単一画面内に 4 つのセクションを縦に配置する（タブ切り替えではなく、リサイズ可能な分割パネル方式）:

| セクション | ヘッダー | 内容 |
|-----------|---------|------|
| **EXPLORER** | 固定ヘッダー | ファイルツリー (`FileTreeView`) |
| **OUTLINE** | 固定ヘッダー | 見出し一覧 (`OutlineView`) |
| **TODO** | 折り畳みヘッダー | TODO/FIXME 一覧 (`TodoView`) |

EXPLORER と OUTLINE の境界にはドラッグ可能なリサイズハンドルがあり、`outlinePanelRatio`（デフォルト 0.35）で比率を制御する。TODO セクションは折り畳み式で、展開時は最大 200px または利用可能領域の 30% を占める。

アウトラインが空（見出しなし）の場合、OUTLINE パネルは 60px の最小高さで「見出しが見つかりません」プレースホルダーを表示する。

### エディタ - サイドバー間の同期メカニズム

同期は 3 つの方向で行われる:

#### 1. ファイルツリー → エディタ（ファイル選択）

`FileTreeView` でノードをタップすると:
1. `fileTreeViewModel.selectedNode` を更新
2. `FileService().readFile(at:)` でファイル内容を非同期読み込み
3. `appViewModel.openInTab(url:content:)` でエディタにテキストを反映
4. `AppState.saveLastFile()` で最後に開いたファイルを永続化

#### 2. エディタ → アウトライン（テキスト変更）

エディタのテキストが変更されると:
1. `AppViewModel` が `outlineViewModel.update(text:)` を呼び出す
2. 300ms デバウンス後にバックグラウンドで見出しを再抽出
3. `items` プロパティの更新が `@Observable` 経由で `OutlineView` に伝播

#### 3. アウトライン → エディタ（行ジャンプ）

`OutlineView` で見出しをタップすると:
1. `appViewModel.previewScrollRatio` を更新（プレビューペイン同期用）
2. `NotificationCenter` で `.jumpToLine` 通知を発行（`userInfo: ["line": item.line]`）
3. `NSTextViewWrapper`（エディタコア）が通知を受信し、該当行にスクロール

この `.jumpToLine` 通知は TODO パネルからの行ジャンプでも共有されており、サイドバー内の異なるセクションから統一的にエディタのスクロール位置を制御できる。

### データフロー図

```
FileTreeView ──(tap)──→ AppViewModel.openInTab() ──→ editorText 更新
                                                          │
                                                          ↓
                                               OutlineViewModel.update()
                                                          │
                                                    (300ms debounce)
                                                          │
                                                          ↓
                                               OutlineView 再描画
                                                          │
                                                       (tap)
                                                          │
                                                          ↓
                                            .jumpToLine Notification
                                                          │
                                                          ↓
                                            NSTextViewWrapper スクロール
```

## Related

- [[エディタコア (NSTextViewWrapper)]] — `.jumpToLine` 通知の受信側
- [[MVVM と Observable パターン]] — `@Observable` による状態伝播の仕組み
- [[AppKit-SwiftUI ブリッジ]] — NSTextView ラップの詳細

## Sources

- `Sources/ViewModels/FileTreeViewModel.swift`
- `Sources/ViewModels/OutlineViewModel.swift`
- `Sources/Views/Sidebar/FileTreeView.swift`
- `Sources/Views/Sidebar/OutlineView.swift`
- `Sources/Views/Sidebar/SidebarView.swift`
- `Sources/Models/FileNode.swift`
- `Sources/Services/FileService.swift`
