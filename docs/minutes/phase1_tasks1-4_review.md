# Phase 1 Tasks 1〜4 ペルソナ間レビュー議事録

**日付**: 2026-04-20
**参加ペルソナ**: Claude（Orchestrator/Architect）、Codex（UI Coder）、Gemini（Researcher/DocWriter）
**対象タスク**: Task 1〜4（ビルド済み・コミット済み）

---

## Task 1: Xcodeプロジェクト作成・ディレクトリ構成

### 実装サマリー
- Package.swift（swift-tools-version:5.9、macOS 14+、swift-markdown 0.7.3依存）
- Sources/{App, Views, ViewModels, Services, Models} のMVVM構成
- 全レイヤーのSwift雛形ファイル生成 → ビルド確認済み

### レビュー

**Gemini**: MVVM構成・依存管理が明確。Package.swiftは今後のモジュール追加にも対応しやすい理想的な出発点。

**Codex**: ディレクトリ構成は拡張性を考慮しており、ビルドやテストのスコープが把握しやすい。

**Claude（Architect判断）**: swift-markdownはApple公式で安定。v0.7.3（cmark-gfm依存）は選択として適切。雛形段階でビルドが通ることをCI代わりに確認できた点は良い。

---

## Task 2: 基本ウィンドウ（3ペイン）

### 実装サマリー
- NavigationSplitView（sidebar/content/detail）
- AppViewModelを@Environment(AppViewModel.self)で注入
- .balanced スタイル、各ペインminWidth設定

### レビュー

**Gemini**: macOSアプリの標準UIパターンに完全適合。@EnvironmentによるViewModel共有はMVVMのベストプラクティス。

**Codex**: @Environment注入のタイミングとライフサイクルに注意が必要。

**Claude（Architect判断）**: @Environmentは`@Observable`クラス専用API（`.environment(obj)`）を正しく使用できており、型安全。NavigationSplitViewの`.balanced`はサイドバー折りたたみ対応のデフォルトとして妥当。

---

## Task 3: フォルダツリー + ファイル開閉

### 実装サマリー
- FileService: 再帰ディレクトリ読み込み（.mdのみ、ディレクトリ優先ソート）
- FileTreeViewModel: @MainActor @Observable、NSOpenPanelでフォルダ選択
- FileTreeView: OutlineGroupでツリー表示、タップでファイル読み込み→AppViewModel反映

### レビュー

**Gemini**: FileService/ViewModel/Viewの責務分担がMVVMに完全適合。@MainActor @Observableの活用は現代的なSwiftUI開発のベストプラクティス。

**Codex**: NSOpenPanelとの連携・OutlineGroupの構成が綺麗で保守性高い。再帰読み込みと表示の分離も良好。

**Claude（Architect判断）**: 懸念点として**非同期処理の未対応**がある。FileService.loadNodes()は現在同期で大規模ディレクトリではUIブロックの可能性。→ Task 5以降のリファクタ時にasync化を検討する。

---

## Task 4: NSTextViewエディタ（基本編集）

### 実装サマリー
- NSTextViewWrapper: NSScrollView+NSTextView、Coordinatorパターン
- モノスペースフォント14pt、allowsUndo、カーソル位置safe保持（range clamp）
- EditorView: @Bindable経由でAppViewModel.editorTextにバインド

### レビュー

**Gemini**:
1. **アーキテクチャ**: AppKitコンポーネント統合の標準パターンで適切。将来機能追加時のNSTextViewWrapper肥大化に注意。
2. **パフォーマンス**: 大量テキスト時にtextDidChange→Binding更新→updateNSViewの連鎖が頻繁に発生するとちらつきの懸念。差分検出ロジックを強化すべき。
3. **改善提案**: updateNSView内で文字列比較後のみ反映（既に実装済み）。NSTextStorageの差分更新をPhase 2で検討。

**Codex**:
1. textViewDidChangeSelectionで選択位置をCoordinatorに保持し、updateNSViewでの競合を回避する設計が望ましい。
2. updateNSVIewは既にstring比較済みだが、スクロール位置のリセット防止も考慮すること。

**Claude（Architect判断・決定事項）**:
- カーソルrange clampは実装済みで基本的な競合を回避。
- **Phase 2向けTODO**: ① textViewDidChangeSelectionでCoordinatorに選択位置キャッシュ ② スクロール位置保持 ③ NSTextStorage差分更新API検討。
- AppViewModel肥大化リスクは認識済み。Task 5完了後にEditorViewModel/PreviewViewModelへの責務分散を実施する。

---

## 次タスク（5〜7）の実装方針議論

### Geminiの推奨

**Task 5（Markdownプレビュー）**:
- `swift-markdown` でAST生成 → HTML変換 → WKWebViewで表示が最も手軽
- Debounce機構（タイプ停止後にプレビュー更新）で応答性確保
- PreviewViewModelをAppViewModelから分離

**Task 6（シンタックスハイライト）**:
- NSTextStorage + NSLayoutManagerを使った実装が自然
- beginEditing/endEditingループで属性変更、無限ループ回避
- HighlightServiceでロジックを分離

**Task 7（全文検索）**:
- SearchViewModelで検索ロジック管理
- まず逐次検索（async）、大規模ファイル向けインデックスはPhase 2

### Codexの推奨

- **実装順序**: Task 5 → Task 6 → Task 7が自然
  - Task 5でMarkdownパース基盤を整え、Task 6はその上にNSTextStorage差分ハイライトを後付けできる
- Task 5でMarkdownServiceに責務を集約（Parser/Renderer分離）し、SwiftUI側にはHTML/AttributedStringを渡す

### Claude（Orchestrator決定）

1. **実装順序**: Task 5 → 6 → 7（Codex推奨に同意）
2. Task 5では `swift-markdown` のDocument型を使い、HTML変換はカスタムVisitorで実装（MarkdownService内）
3. Task 6はTask 5のMarkdownServiceと連携し、同じASTからハイライト範囲を取得する設計を目指す
4. AppViewModel.editorText変化の通知はCombine/.onChangeで各Serviceに伝播させる

---

## 決定事項・アクション

| # | 内容 | タイミング |
|---|------|-----------|
| 1 | Task 5: WKWebViewプレビュー実装（Debounce付き） | 次タスク |
| 2 | Task 5完了後にEditorViewModel/PreviewViewModelへ責務分散 | Task 5完了時 |
| 3 | FileService.loadNodesをasync化 | Task 5〜6の間 |
| 4 | Task 6: NSTextStorageシンタックスハイライト | Task 5後 |
| 5 | Task 7: 全文検索（逐次async） | Task 6後 |
| 6 | Phase 2 TBD: NSTextViewCursorキャッシュ・差分更新 | Phase 2 |
