# Phase 2 Tasks 1〜3 ペルソナ間レビュー議事録

**日付**: 2026-04-20
**参加ペルソナ**: Claude（Orchestrator/Architect）、Codex（UI Coder）、Gemini（Researcher/DocWriter）
**対象タスク**: Phase 2 Task 1〜3

---

## 完了タスクサマリー

| Task | 内容 | コミット |
|------|------|---------|
| 8 | ファイル保存・新規作成（Cmd+S/N, NSSavePanel, ダーティ状態） | c338351 |
| 9 | エラーハンドリング統一（AppError, showAppError） | d905fa3 |
| 10 | 削除・名前変更（コンテキストメニュー, trashItem） | a1e8a88 |

---

## レビュー

### Gemini 品質評価

| Task | スコア | コメント |
|------|--------|---------|
| Task 1（保存・新規） | 5/5 | atomic write・ダーティ状態・NSSavePanel・Cmd対応が堅牢 |
| Task 2（エラー統一） | 5/5 | LocalizedError + 日本語メッセージ + recoverySuggestion で完璧 |
| Task 3（削除・リネーム） | 5/5 | macOS標準UX準拠、自動reload、高い完成度 |

### Codex 指摘事項

1. **NotificationCenterのウィンドウ識別問題**: 複数ウィンドウ起動時、どのEditorに対するSave/Newか識別できない。Responder chainかウィンドウ固有通知が必要。→ **Phase 2 TBD**（現状はシングルウィンドウ前提なので影響小）

2. **renameNode()後の処理漏れ**: 名前変更したファイルが開いていた場合、EditorのdocumentURLと表示が更新されない。→ **要修正（次コミット）**

3. **コンテキストメニューのUX**: TextFieldの初期選択・Enter確定は改善余地あり。→ **Phase 2 TBD**

---

## Claude（Architect）決定事項

### 即時対応: renameNode()後のURL更新

名前変更したファイルが現在開いているファイルだった場合、`appViewModel.selectedFileURL`を新URLに更新する。次コミットで修正。

### Phase 2 残りタスク優先順位（決定）

Gemini/Codexの意見を踏まえ以下で確定：

| 優先度 | タスク | 理由 |
|--------|--------|------|
| 最高 | **スクロール同期**（エディタ↔プレビュー） | UX改善の即効性が最大（両者共通見解） |
| 高 | **GFM拡張**（テーブル/タスクリスト） | 広く使われる記法、欠如が目立つ |
| 高 | **Find & Replace** | テキストエディタの基本機能 |
| 中 | **行番号表示** | コード編集時の利便性 |
| 低 | **テーマ設定** | コア機能充実後でよい |

---

## 次アクション

1. **即時**: renameNode()でopenファイルのURL更新を修正
2. **次タスク**: スクロール同期（WKWebView scrollToFragment or NSTextView offset sync）
