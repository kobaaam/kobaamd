# Phase 2 Tasks 4〜8 ペルソナ間レビュー議事録

**日付**: 2026-04-20
**参加ペルソナ**: Claude（Orchestrator/Architect）、Codex（UI Coder）、Gemini（Researcher/DocWriter）
**対象タスク**: Phase 2 Task 4〜8

---

## 完了タスクサマリー

| Task | 内容 | コミット |
|------|------|---------|
| 11 | スクロール同期（scrollRatio→JS） | db55f3b |
| 12 | GFM拡張（Table/TaskList/Strikethrough） | 18c87e6 |
| 13 | Find & Replace（Cmd+F） | 6957c4c |
| 14 | 行番号表示（LineNumberRulerView） | ad9ef3c |
| 15 | タイトルバー（●ファイル名） | 18c87e6 |

---

## Gemini 評価

**総合評価**: 機能実装は順調。次は品質検証・安定化フェーズへ移行が必要。

- エディタ機能として必要な要素が揃った
- 複数ウィンドウでのNotificationCenter問題は既知の課題（単一ウィンドウ前提で影響小）
- 実機テスト未完了が最大のリスク

**次の優先タスク（Gemini推奨）**:
1. 最近開いたファイル（作業効率直結）
2. テーマ設定（長時間利用の快適性）
3. ウィンドウ状態保存（再起動後の利便性）

---

## Codex 指摘事項

1. **行番号RulerViewのパフォーマンス**: 大量テキストで毎描画サイクルに全行フラグメント再計算の懸念。NSLayoutManagerのinvalidate範囲を絞るか、行番号をキャッシュする最適化が将来必要。

2. **FindReplaceBarのマルチバイト**: Swift String.IndexはGraphemeクラスター単位で動作するため基本的に安全。ただしEmoji等の複合文字でRange計算がズレるエッジケースあり、UTF16View使用を検討。

3. **実行ファイルの場所**: `.build/release/kobaamd`（Mach-O）→ 手動で.appバンドル化済み(`.build/kobaamd.app`)。起動確認済み（PID確認）。

---

## Claude（Architect）決定事項

### 既知バグ・技術的負債（Phase 3対応）
| 項目 | 内容 |
|------|------|
| 複数ウィンドウ問題 | NotificationCenter→Responder chain化（Phase 3） |
| HighlightService全文再描画 | 差分ハイライト最適化（Phase 3） |
| スクロール同期ズレ | HTML reload時のスクロールタイミング（Phase 3） |

### Phase 2 残りタスク計画

| 優先度 | タスク |
|--------|--------|
| 高 | 最近開いたファイル（UserDefaults/NSDocumentController） |
| 中 | ウィンドウ状態保存（最後のフォルダ・ファイルを記憶） |
| 中 | ツールバーアイコン追加（保存・新規・フォルダを開く） |
| 低 | テーマ設定（後回し） |

---

## 動作確認用実行ファイル

`.build/kobaamd.app` を作成済み（release build）。
起動コマンド: `open /Users/h.kobayashi02/atelier/kobaamd/.build/kobaamd.app`
または Finderから直接開く。
