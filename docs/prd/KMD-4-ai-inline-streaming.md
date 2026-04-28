---
linear: KMD-4
status: in-progress
created_at: 2026-04-27
author: kobaamd_implement_code
---

# AIインライン補完のストリーミング対応 — 生成中をリアルタイム表示

## 1. 背景・目的

現在のAIインライン補完（`{{プロンプト}}`記法）は `AIService.complete()` で全文生成完了後にエディタへ一括挿入する仕組みになっている（`AppViewModel.startAIInlineCompletion()`）。長い文章を生成させると数秒〜十数秒フィードバックがない状態が続き、ユーザーはプロセスが止まっているのか不明になる。ストリーミング対応により「AIが書いている様子」がリアルタイムに見えることで、AIとの共同執筆感覚が強まり、kobaamdのビジョン「AIが生成したMarkdownを最も快適に扱えるエディタ」の体験品質が大きく向上する。

## 2. ターゲットユーザーとユースケース

### ペルソナ A — 長文生成ユーザー

長文のセクション（500文字以上）を`{{セクションを詳しく説明して}}`で生成させる場面。プレースホルダー行の後ろにトークンが流れ込む様子を見ながら、生成途中でも内容の方向性を確認できる。

**シナリオ**: `{{このサービスの価値提案を500字で書いて}}` と記述してEnter → トークンが流れ込む → 意図と違う方向だと気づき ⌘. でキャンセル → プロンプトを修正して再実行。

### ペルソナ B — AIアシストパネル利用者

`AIAssistPanel` で質問・要約を行うユーザー。現在は完了まで待機しているが、ストリーミングにより回答が徐々に現れる体験に変わる。

## 3. 機能要件

### 必須要件

- `AIService` にストリーミング用メソッドを追加（OpenAI `stream: true` SSE / Anthropic SSE 両対応）、`AsyncThrowingStream<String, Error>` を返す API を設計
- `AppViewModel.startAIInlineCompletion()` をストリーミング版に切り替え: トークン受信ごとにエディタのプレースホルダー位置を `replaceSubrange` で更新
- 生成中キャンセル: ⌘. でアクティブな `Task` を `cancel()` する
- `AIAssistPanel` も同様にストリーミング表示へ対応（`result` を逐次更新）

### オプション要件

- 生成中のステータスバー表示（「AI生成中... (⌘. でキャンセル)」）

## 4. 非機能要件

- **パフォーマンス**: ストリーミング中の `editorText` 更新頻度は最大 30fps（33ms間隔）でバッファリング。HighlightService / プレビュー再描画との競合を防ぐ。
- **アクセシビリティ**: キャンセルショートカット（⌘.）をメニュー項目としても公開し、キーボードのみで操作可能に。
- **macOS整合性**: `URLSession` の `bytes(for:)` API（macOS 12+）を使いSSEを処理。`Task` のライフサイクル管理で不要なバックグラウンド処理を残さない。

## 5. UI/UX

```
エディタ（生成前）:
  ...
  {{この節を詳しく説明して}}   ← Enter押下で実行

エディタ（ストリーミング中）:
  Markdownエディタとは、マーク  ← トークンが逐次流れ込む

ステータスバー（生成中）:
  42行 / 310語  |  AI生成中... ⌘. でキャンセル  |

AIAssistPanel（ストリーミング中）:
+------------------------------------------+
|  質問: この段落を要約して                 |
|  回答: このドキュメントは...|  ← 逐次更新  |
+------------------------------------------+
```

- 生成中: ステータスバーに `ProgressView()` スピナー + キャンセル案内を表示
- 完了後: ステータスバーを通常表示に戻す

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `{{500文字以上を生成させるプロンプト}}` を実行すると、完了待ちではなくトークンが逐次エディタに挿入される
- [ ] ストリーミング中に ⌘. を押すと生成が中断され、それまでに生成されたテキストがエディタに残る
- [ ] OpenAI / Anthropic 両プロバイダーでストリーミングが動作する
- [ ] `AIAssistPanel` での質問もストリーミング表示になる（回答が徐々に現れる）
- [ ] ストリーミング完了後、エディタの HighlightService が正常に動作し、ハイライトが崩れない

## 7. テスト戦略

### 単体テスト対象ファイル

- `Sources/Services/AIService.swift`（既存・大幅改修）: ストリーミングメソッドのテスト（モックURLSession使用）
  - テストケース: 正常ストリーム・途中エラー・キャンセル・空レスポンス・OpenAI形式・Anthropic形式
- `Sources/App/AppViewModel.swift`（既存・改修）: `startAIInlineCompletion()` のストリーミング版動作（モックAIService使用）

### 手動確認項目

1. 長文生成（500字以上）でトークンが逐次表示されることを確認
2. ⌘. キャンセルで生成が即座に停止し、アプリが正常な状態に戻ることを確認
3. OpenAI・Anthropic 両プロバイダーで動作確認
4. ストリーミング完了後のハイライト・プレビュー再描画が正常であることを確認

## 8. 想定リスク・依存

### 影響範囲マップ
<!-- 実装前に必ず埋める。Codex プロンプトの「触れないもの一覧」の根拠になる -->

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Services/AIService.swift` | 変更 | ストリーミングAPI追加（非破壊的: 既存 `complete()` は保持し新メソッドを追加） |
| `Sources/App/AppViewModel.swift` | 変更 | `startAIInlineCompletion()` のストリーミング版切替。`isAIGenerating` プロパティ追加 |
| `Sources/Views/AI/AIAssistPanel.swift` | 変更 | `result` の逐次更新に対応 |
| `Sources/App/AppCommand.swift` | 変更 | `cancelAIGeneration` コマンドの追加のみ |
| `Sources/Views/MainWindowView.swift` | 変更 | `StatusCommandBar` へのAI生成状態表示追加のみ |
| `Sources/App/kobaamdApp.swift` | 変更 | `cancelAIGenerationRequested` Notification.Name 追加のみ |

**共有コンテナへの注意**:

- `AppViewModel.swift` はタブ管理・保存・フォーマット・PDF エクスポート等の複数機能を持つ。`startAIInlineCompletion()` メソッドと `isAIGenerating: Bool` プロパティのみ変更・追加する。他のメソッドには触れてはいけない。
- `MainWindowView.swift` は `StatusCommandBar`, `SplitDivider`, `KobaDivider`, `KbdHint`, ツールバー等を含む。PDF エクスポートステータス表示（`pdfStatusMessage`, `isPDFExporting` 周辺）と既存の `StatusCommandBar` レイアウトには触れてはいけない。AI生成中ステータスの表示のみ追加する。
- `AppCommand.swift` には既存の save/newFile/find/openFolder/aiAssist/toggleSidebar/newTab/formatDocument/exportPDF コマンドがある。`cancelAIGeneration` を追加するのみで、既存コマンドの enum ケースには触れてはいけない。
- `kobaamdApp.swift` の Notification.Name extension と AppDelegate には触れてはいけない。`cancelAIGenerationRequested` の追加のみ。
- `AIAssistPanel.swift` の UIレイアウト（Header/PromptInput/Result/Errorセクション）構造は維持する。`run()` メソッドをストリーミング対応に変更するのみ。

**変更してはいけない箇所**:
- `AppViewModel` のタブ管理メソッド群 (`openInTab`, `switchToTab`, `closeTab`, `flushActiveTab`, `activate`)
- `AppViewModel` の保存関連 (`saveCurrentFile`, `saveAs`, `markSaved`, `markEdited`, `scheduleStatsUpdate`)
- `AppViewModel` の PDF エクスポート関連 (`exportPDF`, `handlePDFExportResult`, `isPDFExporting`, `pdfStatusMessage`)
- `AppViewModel` の `formatCurrentDocument()`
- `AIService` の既存 `complete()` メソッドシグネチャ（後方互換性維持）
- `NSTextViewWrapper` の `⌘Return` 処理ロジック（`.aiInlineRequested` 通知の投げ方）
- `EditorView` の `.aiInlineRequested` 受信処理（`startAIInlineCompletion()` の呼び出し側）

### その他リスク

- ストリーミング中の `editorText` 書き換えと HighlightService・プレビュー再描画の競合。更新頻度をバッファリングして制御する必要がある。
- OpenAI / Anthropic でSSEフォーマットが異なるため分岐実装が必要。

## 9. 計測・成果指標

リリース後評価のため未定義。候補:

- AI生成の平均所要時間（ストリーミング前後比較）
- キャンセル操作の発生率

## 10. 参考資料

- OpenAI API: `stream: true` + `text/event-stream`
- Anthropic API: SSE streaming
- Apple Developer: URLSession `bytes(for:delegate:)` (macOS 12+)
- iA Writer: AI機能でのインライン生成体験
