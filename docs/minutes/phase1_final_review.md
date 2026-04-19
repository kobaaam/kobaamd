# Phase 1 MVP 最終レビュー議事録

**日付**: 2026-04-20
**参加ペルソナ**: Claude（Orchestrator/Architect）、Codex（UI Coder）、Gemini（Researcher/DocWriter）
**対象**: Phase 1 Tasks 1〜7 完了後の最終評価

---

## Phase 1 完了サマリー

| Task | 内容 | コミット |
|------|------|---------|
| 1 | Package.swift + ディレクトリ構成 | 480f7ed |
| 2 | 3ペインウィンドウ（NavigationSplitView） | 07dbdcc |
| 3 | フォルダツリー + ファイル開閉 | c8460e1 |
| 4 | NSTextViewエディタ（基本編集） | 4a6fce8 |
| 5 | swift-markdown リアルタイムプレビュー | 7f4909c |
| 6 | シンタックスハイライト（正規表現ベース） | 98a5d01 |
| 7 | 全文検索 | 400d7c0 |

---

## Gemini レビュー

### 品質評価: **4.5 / 5点**

**高評価の根拠**:
- コア機能の網羅性（MVPとして必須の全機能を実装）
- 技術選定の的確さ（swift-markdown/WKWebView/NSTextStorage等）
- MVVM・サービス層分離によるコードの可読性・保守性
- 開発中の課題（Document名前衝突等）への即座な対応

**減点理由（-0.5点）**:
- ファイル保存機能が未実装（エディタの根幹機能）
- エラーハンドリング・ユーザーフィードバックが最低限

---

## Codex レビュー

### 潜在バグ・エッジケース

1. **FileService + NSOpenPanel**: 大量ファイルフォルダ選択時、ツリービュー同期完了前にOpenPanelが閉じると状態不整合が発生する可能性。ファイルリスト読み込み完了までローディング状態を保持すべき。

2. **HighlightService**: NSTextStorageへの更新がメインスレッド以外から行われるとNSTextViewとのレースが発生する懸念。ハイライト処理は必ずメインスレッドで実行すること（現実装はtextDidChange内のため現状は安全だが、将来的な非同期化に注意）。

3. **SearchViewModel**: Task.detachedの古い検索結果が後から適用される可能性。検索クエリ変更時に前のTaskをキャンセルする仕組みが未実装。

### UIパフォーマンス改善提案

- フォルダツリーに`LazyVStack`活用（大量ファイル時の描画コスト削減）
- HighlightService: 全文再ハイライト → 変更範囲のみ差分更新へ
- PreviewViewModel: HTML生成をバックグラウンドキューで実施後にmain queue反映

---

## Claude（Architect）最終評価・決定事項

### Phase 1評価

Phase 1のゴール（ビルドが通るMVP）は完全達成。アーキテクチャの一貫性も高く、Phase 2拡張の土台として十分。

Codexが指摘したSearchViewModelのキャンセル問題は**既知のバグ**として記録する。次のコミットで修正する。

### Phase 2優先実装順序（決定）

| 優先度 | 内容 | 担当 |
|--------|------|------|
| **最高** | ファイル保存（Cmd+S）・新規作成 | Codex |
| **高** | SearchViewModel: 旧Taskキャンセル修正 | Claude |
| **高** | エラーハンドリング（alert表示統一） | Codex |
| **中** | ファイル/フォルダの削除・名前変更（コンテキストメニュー） | Codex |
| **中** | エディタ/プレビューのスクロール同期 | Codex |
| **中** | Find & Replace | Codex |
| **低** | GFM拡張（テーブル、タスクリスト） | Codex |
| **低** | テーマ・フォントカスタマイズ | Codex |
| **低** | 行番号・ミニマップ | Codex |

### Phase 2で検討するTBD事項（引き継ぎ）

- [ ] HighlightServiceの差分ハイライト（性能最適化）
- [ ] AIキー管理: Keychain経由（方針確定済み、Phase 2実装）
- [ ] TreeSitter移行（Phase 2以降でのハイライト強化）
- [ ] エディタ/プレビュースクロール同期の実装方式検討
- [ ] ファイルシステム監視（FSEventsによる外部変更検知）

---

## ハーネス設計（運用保守向け）

ユーザーからの要求に基づき、以下のハーネス設計を追加実施する（別議事録参照）。

- **ビルドCI**: `swift build`をhookで自動実行
- **ペルソナ間議事録**: 各タスク完了時にdocs/minutesへ記録（本ファイルが実例）
- **CLAUDE.md更新**: フェーズ進行に合わせて引き継ぎ資料を更新

---

*本議事録はClaude/Codex/Geminiのペルソナ間レビューを基に作成。*
