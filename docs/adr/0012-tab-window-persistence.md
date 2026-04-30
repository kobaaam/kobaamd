# ADR-0012: UUID ベースのタブ状態管理

- **Status**: accepted
- **Date**: 2026-02
- **Deciders**: 人間 / Claude
- **Related**: ADR-0001 (MVVM + @Observable)

## Context

kobaamd はマルチタブ Markdown エディタであり、複数のファイルを同時に開いてタブで切り替える機能が必要である。タブの状態管理においては、以下の設計判断が求められた。

1. **タブの一意識別**: 同一ファイルの重複オープン防止と、未保存（Untitled）タブの識別をどう両立するか
2. **タブとエディタの同期**: アクティブタブの切り替え時に、エディタの内容（テキスト・ダーティフラグ・ファイルURL）をどう保存・復元するか
3. **ウィンドウモデル**: macOS の `NSDocument` / `WindowGroup(for:)` を採用するか、独自のタブモデルで管理するか

技術的制約として、kobaamd は単一ウィンドウ・マルチタブのアーキテクチャを採用しており、`@Observable` ベースの MVVM パターン（ADR-0001）上に構築する必要があった。

## Decision

**UUID ベースの独自タブモデル + ViewModel 内フラッシュ方式**を採用した。

### タブモデル (`EditorTab`)

```swift
struct EditorTab: Identifiable, Equatable {
    let id: UUID          // 生成時に自動採番、不変
    var url: URL?         // nil = 未保存タブ
    var content: String   // タブごとのテキスト内容
    var isDirty: Bool     // 未保存変更フラグ
}
```

- `id` はインスタンス生成時に `UUID()` で自動生成される不変の識別子
- `url` はオプショナルで、`nil` の場合は「Untitled」タブとして扱う
- 同一ファイルの重複オープン防止は `url` で判定する（`openInTab` で既存タブの `url` と照合）

### タブ切り替え時のフラッシュ方式

`AppViewModel` がエディタの現在状態（`editorText`, `isDirty`, `selectedFileURL`）を一元管理し、タブ切り替え時に以下の手順で同期する。

1. **flushActiveTab()**: 現在のエディタ状態をアクティブタブの `EditorTab` 構造体に書き戻す
2. **activate(tab:)**: 切り替え先タブの内容をエディタ状態に読み込む

この方式により、同時に「編集中」の状態を持つのは常に 1 タブのみとなる。

### 重複防止ロジック

`openInTab(url:content:)` は、まず `tabs.first(where: { $0.url == url })` で既存タブを検索し、見つかれば `switchToTab` するだけで新規タブを作らない。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| URL ベース ID（ファイルパスを ID にする） | ファイルと 1:1 対応が自明 | 未保存タブ（Untitled）の ID が空になり一意性を保証できない。リネーム時に ID が変わる | 未保存タブの扱いが煩雑になり、UUID の方がシンプル |
| NSDocument ベース | macOS 標準の自動保存・復元・バージョン管理を活用可能 | SwiftUI + `@Observable` との統合が困難。NSDocument は AppKit 中心の設計で、ViewModel パターンと責務が重複する | ADR-0001 の MVVM 方針と相性が悪く、制御の主導権が NSDocument フレームワークに移る |
| `WindowGroup(for:)` ベース（マルチウィンドウ） | macOS ネイティブのウィンドウ管理を活用可能 | タブ間の状態共有が困難（各ウィンドウが独立した状態を持つ）。サイドバー・プレビュー等の共有 UI との連携が複雑化 | 単一ウィンドウ内でタブを切り替える UX を目指しており、マルチウィンドウモデルは過剰 |

## Consequences

### Positive
- **シンプルな実装**: `EditorTab` は 4 プロパティの軽量 struct であり、理解・テストが容易
- **未保存タブの自然な扱い**: UUID により Untitled タブも一意に識別でき、複数の未保存タブを同時に開ける
- **ViewModel 一元管理**: エディタ状態が `AppViewModel` に集約されており、タブ切り替え・保存・AI 補完などの機能が同一レイヤーで連携できる
- **重複防止の明快なロジック**: URL 照合による既存タブ検出がワンライナーで実現

### Negative
- **アプリ再起動時のタブ復元なし**: UUID はメモリ内でのみ有効であり、`EditorTab` は `Codable` でないため、アプリ終了時にタブ状態が失われる。将来的に永続化が必要になる可能性がある
- **単一アクティブ編集モデル**: 同時に 1 タブしか編集状態を持てないため、バックグラウンドでの自動保存や差分検知はアクティブタブに限定される

### Risks
- **タブ数増加時のパフォーマンス**: `tabs` 配列の線形探索（`firstIndex(where:)`, `first(where:)`）はタブ数が数十を超えると影響が出る可能性がある。ただし、エディタの一般的な使用では問題にならない規模
- **永続化の後付け**: タブ復元を将来実装する場合、`EditorTab` を `Codable` にし、UUID の再生成 vs 保存の判断が必要になる。URL ベースでの復元であれば UUID を再生成しても問題ないが、未保存タブの復元には content の永続化も必要

## References

- `Sources/Models/EditorTab.swift` — タブモデル定義
- `Sources/App/AppViewModel.swift` — タブ管理ロジック（openInTab, closeTab, flushActiveTab, activate）
- `Sources/Views/Editor/TabBarView.swift` — タブバー UI
- ADR-0001: MVVM + @Observable アーキテクチャ
