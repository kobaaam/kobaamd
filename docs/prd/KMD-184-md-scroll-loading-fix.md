---
linear: KMD-184
status: in-progress
created_at: 2026-05-05
author: kobaamd_implement_code (Claude Opus)
---

# md スクロール中の loading 頻発の修正（perf regression）

## 1. 背景・目的

ユーザー報告: md ファイルを開いてスクロールしようとすると `loading` 表示が頻発する。「軽量なエディタ」が kobaamd ビジョンの中核だが、スクロール体験の劣化はビジョン根幹に反する。

過去のスクロール / プレビュー回り改修（KMD-65 Backlinks、KMD-67 frontmatter、KMD-68 SQLite index、KMD-69 MCP）でメインスレッド負荷が増えた可能性。また、`previewScrollRatio` 経由で `MarkdownWebView.updateNSView` がスクロール毎に走り、AI overlay 計算と JS evaluate が main thread を消費している恐れがある。

ゴールは **スクロール 60fps 維持 / loading 表示なし**。

## 2. ターゲットユーザーとユースケース

- 1,000 行クラスの md ファイルをエディタで開いてスクロールする全ユーザー
- 50 コードブロック / 10 Mermaid を含むテック記事を編集するユーザー

## 3. 機能要件

### 必須要件

1. **`PreviewView` の `previewViewModel.isRendering` 表示を抑制**:
   - 初回ロード時（`shellHTML` が空、または `bodyHTML` がまだ webview に渡されていない）のみ ProgressView を出す
   - 差分更新（`editorText` 変更による update）時には出さない（更新は数十 ms で終わるためチラつき源）
   - 既存の `isRendering` フラグはそのまま残し、view 側で「初回ロード判定」でゲートする

2. **`EditorObserver.subscribeScroll` のスクロール毎 main thread 処理を軽量化**:
   - `updateAIOverlayPosition` は **AI インライン関連状態（`isAIInlinePromptVisible` / `pendingAIText` / `isAIGenerating`）がアクティブなときのみ呼ぶ**
   - 通常のスクロールでは layoutManager への問い合わせを発生させない
   - ratio.wrappedValue の更新自体は維持（preview 同期に必要）

3. **`MarkdownWebView.syncScroll` の throttle**:
   - スクロール毎に `evaluateJavaScript` を送ると WebKit IPC コストが重い
   - 16ms throttle（1 frame）で間引く。最後の値は必ず反映する trailing-edge 方式

### オプション要件

- `PerfLogger` に `Scroll` イベントを追加して計測ログを出す（後追い検証用）
- 修正効果が出ているか確認するためのスナップショット計測スクリプトは別チケット

## 4. 非機能要件

- パフォーマンス: スクロール中の main thread block 16ms 以内（60fps 維持）
- アクセシビリティ: ProgressView の VoiceOver 影響なし（出さなくなるので逆に改善）
- macOS との整合性: macOS 14 以降、TextEditor / WKWebView の標準 API のみ使用

## 5. UI/UX

スクロールしても loading インジケータが見えなくなる。プレビューの差分更新は debounce 300ms 後に瞬時に置き換わる（既存挙動）。初回ロードのみ「Color.kobaSurface」プレースホルダ → bodyHTML 反映に切り替わる際に短く ProgressView が出る（許容）。

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] 1,000 行 / 50 コードブロック / 10 Mermaid の md でスクロール 30 秒、loading 表示なし
- [ ] スクロール中の main thread block 16ms 以内（PerfLogger ログで確認、または Instruments の Time Profiler）
- [ ] 既存テストが pass する（`swift test` 全 green）
- [ ] エディタ→プレビュー scroll 同期は引き続き動く（preview が editor のスクロールに追従する）
- [ ] AI インラインオーバーレイは AI 関連状態 active 時のみ正しく追従する

## 7. テスト戦略

- 単体テスト:
  - `PreviewView` の isRendering 表示分岐は SwiftUI 上のロジックなので単体テスト追加は困難。回帰防止は手動 + コードレビュー
  - `EditorObserver` の `updateAIOverlayPosition` は MainActor isolated でテスト困難。条件分岐の確認はコードレビューで担保
  - `MarkdownWebView` の throttle は coordinator 内部状態の単体テストを追加可能
- スナップショット: 該当箇所は性能改善であり UI スナップショット差分なし
- 手動確認:
  - 1,000 行の md を開きスクロール、loading が出ないこと
  - AI インライン補完を使ってスクロール、overlay が正しく追従すること
  - プレビューと editor の scroll 同期が引き続き機能すること

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Views/Preview/PreviewView.swift` | 変更 | `previewViewModel.isRendering` 表示条件を「初回ロード時のみ」に絞る。`@State private var hasFirstBodyHTML: Bool` を追加 |
| `Sources/Views/Editor/NSTextViewWrapper.swift` | 変更 | `EditorObserver.subscribeScroll` 内で `updateAIOverlayPosition` の呼び出しを AI 関連状態 active 時のみに限定 |
| `Sources/Views/Preview/MarkdownWebView.swift` | 変更 | Coordinator に `lastSyncScrollAt: ContinuousClock.Instant` と `pendingScrollRatio` を持ち、`syncScroll` を 16ms throttle |

**共有コンテナへの注意**:

- `NSTextViewWrapper.swift` は editor の中核。AI overlay / line highlight / scroll observer / event monitor が同居している。今回触るのは `subscribeScroll` の boundsDidChange callback 内のみ。下記「変更してはいけない箇所」を厳守する
- `PreviewView.swift` は preview と D2 preview 両方を持つ。今回触るのは Markdown プレビュー側 (`isD2File == false` 経路) のみ
- `MarkdownWebView.swift` は updateNSView と Coordinator が同居。`updateNSView` の判断ロジック（差分更新 vs シェル再ロード）は触らない

**変更してはいけない箇所**:

- `EditorObserver.subscribeSelection` 内のロジック（line highlight, cursor block notification, key event monitor）
- `EditorObserver` の `handleAutoListReturn`, `handleCmdZ`, `highlightCurrentLine`, `refreshHighlightForThemeChange`
- `MarkdownWebView.updateNSView` の差分判定ロジック（`isLoaded`, `lastShellHTML`, `lastBodyHTML` の比較）
- `MarkdownWebView` の `injectBody` / `highlightBySourceLine` / `exportPDF`
- `PreviewViewModel.update` の debounce 300ms / Task.detached / shellHTML/bodyHTML 生成（既存挙動を変えない）
- `D2PreviewView` 全体
- `MarkdownService` 全体（パース・レンダリング処理）
- TreeSitter 系（今は使われていないが将来再導入のため触らない）
- `BacklinksViewModel`, `OutlineViewModel`, `TodoViewModel`, `TagsViewModel` の処理
- `AppViewModel.previewScrollRatio` / `aiInlineOverlayPosition` のプロパティ宣言

### その他リスク

- 既存コードへの影響:
  - `updateAIOverlayPosition` のスキップ条件を間違えると AI overlay が追従しなくなる → 厳格にテスト
  - `syncScroll` の throttle で trailing-edge を実装しないと、最終位置が反映されず preview がずれる → trailing flush 必須
- 互換性: Public API 変更なし、UserDefaults / コマンド名変更なし。**非破壊的変更**
- 外部依存: なし

## 9. 計測・成果指標

- スクロール中の `[PERF]` ログで `WebViewLoad` 以外のイベント（追加できるなら `ScrollSync`）が 16ms 以内に収まる
- ユーザー報告（KMD-184）の loading 頻発が消えること

## 10. 参考資料

- KMD-5 (TreeSitter incremental highlight) — 触らない
- KMD-65 (Backlinks pane) — 触らない（refresh はタブ切替のみ）
- KMD-69 (MCP server) — 別プロセス、無関係
- 既存の WKWebView throttle パターン: `injectBody` の callAsyncJavaScript

## 11. Gemini 調査ログ

（本タスクは perf regression の局所修正のため Gemini 呼び出しなし）
