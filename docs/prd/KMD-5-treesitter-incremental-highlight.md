---
linear: KMD-5
status: in-progress
created_at: 2026-04-25
author: kobaamd_research_create_ticket / kobaamd_implement_code
---

# TreeSitterによるシンタックスハイライト高速化

## 1. 背景・目的

Phase 4ロードマップに「TreeSitter」が明記されており、現在の `HighlightService` は正規表現ベースの全文再スキャン方式になっている。`highlight()` が呼ばれるたびに `NSTextStorage` 全体を走査するため、AIが生成した数千行の長文ドキュメントでは編集のたびに highlight レイテンシが蓄積する想定がある。TreeSitter は増分パース（変更箇所のみ再解析）をサポートし、ドキュメントサイズに対して O(変更量) でハイライトを更新できる。Macで最も快適なMarkdownエディタを目指す上で、長文でもキーストロークが詰まらないことは非交渉の要件である。

**今回スコープの方針**: 大規模な書き換えを避け、最小限の incremental migration として
1. `SwiftTreeSitter` + `tree-sitter-markdown` を `Package.swift` に追加し、ビルドに乗せる
2. 新規 `TreeSitterHighlightService` を導入し、AST ベースの増分パース API を提供する
3. 既存 `HighlightService`（正規表現版）は **温存して**フォールバックとして利用する
4. `HighlightServiceProtocol` で両者を切り替え可能にする
を行う。NSTextStorage / NSTextView 配線への波及は最小限にし、後続 PR で本配線を進められる足場を作る。

## 2. ターゲットユーザーとユースケース

### ペルソナ A — 長文ドキュメント編集者

AIに大きなドキュメント（2000行以上の仕様書・READMEなど）を生成させてそのまま kobaamd で編集するユーザー。長文になるほどハイライト処理の負荷が体感品質に直結する。

**シナリオ**: 5000行の仕様書を Claude 生成後に kobaamd で開く → TreeSitter 移行後はキーストロークごとのハイライト更新が一定速度を保ち、快適に編集できる。ユーザーはハイライト処理の存在を意識しない。

## 3. 機能要件

### 必須要件

- Swift製TreeSitterバインディング (`SwiftTreeSitter`) と `tree-sitter-markdown` 文法を `Package.swift` に追加
- 新規 `TreeSitterHighlightService` を実装し、`NSTextStorage` 全体への初回ハイライトと、編集範囲ベースの増分ハイライト API (`applyIncrementalHighlight(textStorage:editedRange:changeInLength:)`) を提供
- 既存正規表現ハイライトと出力カラースキームの互換性を保持（`AppState.shared.selectedTheme` の既存カラートークンを流用）
- フォールバック: TreeSitter のロード失敗・パース失敗時は既存 `HighlightService.highlight()` に委譲してクラッシュしない
- `HighlightServiceProtocol` を導入し、既存正規表現版と TreeSitter 版を同じインターフェースで扱えるようにする

### オプション要件

- GFM拡張（table / strikethrough / autolink）への追加ハイライト対応
- コードブロック内の言語別シンタックスハイライト（`SwiftTreeSitter` の言語注入機能を活用）
- `EditorObserver` から発見した `NSTextView.textStorage` への delegate 配線（本 PR ではスタブのみ、本配線は別 PR）

## 4. 非機能要件

- **パフォーマンス**: 1000行ドキュメントで1キーストロークあたりのハイライト更新 < 16ms（60fps維持）目標。5000行でも < 33ms（30fps）目標。本 PR では SwiftTreeSitter の AST 構築までを最低限担保し、本格的な計測は後続 PR で行う。
- **アクセシビリティ**: ハイライト色は既存 `AppState.shared.selectedTheme` の定義を流用し、コントラスト比は維持。変更なし。
- **macOS整合性**: ハイライト適用は `@MainActor`。重い増分パースはバックグラウンドキューで実行可能な API 形状を保つ。

## 5. UI/UX

ユーザーに見える変化なし（Phase 4 として段階的に取り込む基礎工事）。外観・色・スタイルは既存と同等。設定画面への追加なし。

内部アーキテクチャ（変更後）:

```
NSTextStorage / NSTextView
        |
        v
HighlightServiceProtocol  ----+
   ^               ^          |
   |               |          |
HighlightService   TreeSitterHighlightService
(正規表現・既存)   (AST 増分・新規)
                              |
                              v (パース失敗時 fallback)
                        HighlightService.highlight()
```

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `swift build` が通る（SwiftTreeSitter / tree-sitter-markdown 依存の追加を含む）
- [ ] `swift test` の既存テストがすべて PASS する（`HighlightServiceTests` を含む）
- [ ] `TreeSitterHighlightService` の単体テスト（空文字列・小規模 Markdown・パース不能入力でのフォールバック）が追加されて PASS する
- [ ] 見出し・コードブロック・太字・斜体・リンクのハイライトが既存テスト経由で同等の属性を返す（既存 `HighlightServiceTests` 互換）
- [ ] TreeSitterパースに失敗するドキュメントでもクラッシュせずフォールバックでハイライトされる

## 7. テスト戦略

### 単体テスト

- 既存 `Tests/kobaamdTests/HighlightServiceTests.swift` はそのまま維持（互換性確認）
- 新規 `Tests/kobaamdTests/TreeSitterHighlightServiceTests.swift`:
  - 空文字列でクラッシュしない
  - 見出し・コードブロックに `foregroundColor` 属性が付与される
  - 故意のパース不能入力（例: 巨大なバイナリ風文字列）でフォールバックされ落ちない

### 手動確認項目

- アプリを起動し、エディタでの編集が破綻していないこと（NSTextView 配線は最小限のため、見た目変化なしを期待）
- 既存ハイライト（プレビュー側 / EditorObserver の現在行ハイライト）が壊れていない

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Package.swift` | 変更 | `tree-sitter/swift-tree-sitter@main` + `tree-sitter-grammars/tree-sitter-markdown@split_parser` を依存追加（当初 ChimeHQ 系列を予定したが、tree-sitter-markdown 公式 SPM 対応の `split_parser` ブランチ系列へ実装中に切替） |
| `Package.resolved` | 自動生成（追加） | SPM が依存解決時に生成。実装後に発覚した想定外の追加だが、SPM 規約上コミット対象であり問題なし |
| `Sources/Services/HighlightServiceProtocol.swift` | 追加 | 新規プロトコル定義 |
| `Sources/Services/HighlightService.swift` | 変更（最小） | `HighlightServiceProtocol` 準拠の declaration を追加（実装は不変） |
| `Sources/Services/TreeSitterHighlightService.swift` | 追加 | TreeSitter ベースの新ハイライタ。失敗時は内部で `HighlightService` を呼ぶ |
| `Tests/kobaamdTests/TreeSitterHighlightServiceTests.swift` | 追加 | 新ハイライタの単体テスト |
| `Tests/kobaamdTests/HighlightServiceTests.swift` | 不変 | 既存 API の互換性検証として温存 |

**実装中の方針修正メモ**:
- 当初 PRD では `ChimeHQ/SwiftTreeSitter` + `mattmassicotte/tree-sitter-markdown@feature/spm` を採用予定だったが、後者のブランチが実在しないことが build 時に判明。代替として **公式の `tree-sitter/swift-tree-sitter` + `tree-sitter-grammars/tree-sitter-markdown@split_parser`** を採用した。両者は同じ Matt Massicotte 系列の実装で、SPM 公式対応かつ `Language(language:)` API も互換。
- `Node.kind` プロパティは存在せず、正しくは `Node.nodeType: String?`。Codex 修正で `switch node.nodeType ?? ""` に変更済み。

**共有コンテナへの注意**:
- 対象ファイルを使っている他機能:
  - `HighlightService` を import しているのは現状テストのみ。`EditorObserver` / `NSTextViewWrapper` は `TextEditor` を使っており、`HighlightService` は直接呼ばれていない。
- 変更してはいけない箇所:
  - 既存 `HighlightService.highlight(_ textStorage:)` のシグネチャと正規表現ロジック（KMD-9 / KMD-4 PRD で「シグネチャは変更不可」と明記されているため）
  - `Sources/Views/Editor/NSTextViewWrapper.swift`（macOS 26 不可視バグ回避コードを温存）
  - `Sources/Views/Editor/EditorObserver`（カーソル行ハイライト・スクロール同期の既存挙動）
  - `Sources/Views/Color+Koba.swift` / `AppState.shared.selectedTheme` の既存カラートークン
  - `AppCommand` / `Notification.Name` の既存 case

### その他リスク

- **依存追加によるビルド時間増加**: SwiftTreeSitter は ABI13 の C ライブラリを取り込むため初回ビルドが重い。CI / pre-commit が遅くならないか後続観察。
- **SwiftTreeSitter のリソース解決**: `TreeSitterMarkdown` 言語のクエリファイル（`highlights.scm` 等）が SPM リソースとして取れない場合は、必要に応じて空クエリ + 最低限のノード判別ロジックでスタートする（後続 PR で完全移植）。
- **macOS 26 ベータ TextEditor 制約**: 本配線（NSTextStorageDelegate 経由のハイライト）は本 PR では扱わない。後続 PR でメジャーリリース後の NSTextView 復帰と合わせて行う。
- **ABI 互換**: `SwiftTreeSitter` のメジャー更新時はトレッキング必要。`Package.swift` で範囲指定する。

## 9. 計測・成果指標

未計測。後続 PR で 1000 行 / 5000 行ベンチマークを `Tests/kobaamdTests/HighlightBenchmarks.swift` 等に追加する想定。

## 10. 参考資料

- `SwiftTreeSitter`: https://github.com/ChimeHQ/SwiftTreeSitter
- `tree-sitter-markdown`: https://github.com/tree-sitter-grammars/tree-sitter-markdown
- Neovim / Helix: TreeSitter incremental ハイライトの参考実装
- Phase 4ロードマップ (`CLAUDE.md`)
