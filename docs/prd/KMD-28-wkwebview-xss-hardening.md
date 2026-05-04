---
linear: KMD-28
status: in-review
created_at: 2026-04-30
updated_at: 2026-05-04
author: claude (kobaamd_create_prd) / updated by kobaamd_rework_issue
---

# WKWebView XSS 対策（MarkdownWebView / D2WebView / ConfluenceService）

## 1. 背景・目的

kobaamd は WKWebView を用いて Markdown プレビュー、D2 ダイアグラム表示、Confluence エクスポートを行っている。2026-04-30 のセキュリティ全体走査で、以下 3 箇所に HTML/JavaScript インジェクションの脆弱性が検出された。

1. **MarkdownWebView.swift:46-56** — `injectBody` で HTML を JS テンプレートリテラルに直接埋め込み。エスケープが `\`, バッククォート, `$` の 3 文字のみで、`</script>` タグや改行を含む入力でスクリプト注入が可能
2. **D2WebView.swift:56** — D2 CLI が生成した SVG を `\(svg)` で HTML テンプレートに文字列補間。SVG 内に `<script>` タグが含まれていた場合 WKWebView 内で実行される
3. **ConfluenceService.swift:201-209** — `visitLink` / `visitImage` で URL (`dest`, `src`) を HTML 属性にエスケープなしで埋め込み。`javascript:` スキームや `"` を含む URL で属性値の脱出・スクリプト注入が可能

kobaamd のビジョンは「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」であり、AI 生成コンテンツは予測不能な文字列を含む可能性が高い。安全なレンダリングは信頼性の土台であり、Phase 4 以降の機能拡張（PDF Export 等）に進む前に修正が必須。

## 2. ターゲットユーザーとユースケース

### ペルソナ

* **開発者 A**: AI チャットで生成された Markdown（コードブロック含む）をプレビューで確認する。コードブロック内に `</script>` やバッククォートが含まれることがある

### ユースケース

1. バッククォート 3 連（コードフェンス）を含む Markdown をプレビューで正常に表示できる
2. 悪意ある `<script>` タグを含む SVG が D2WebView で無害化されて表示される
3. `javascript:alert(1)` のような URL が Confluence エクスポート時にサニタイズされる
4. `"onmouseover="alert(1)` のような属性脱出を狙う URL が無害化される

## 3. 機能要件

### 必須要件

* **MR-1**: MarkdownWebView の `injectBody` を `callAsyncJavaScript` のパラメータバインディングに変更し、HTML 文字列を JS 変数として安全に渡す。手動エスケープ（3 文字置換）を廃止する
* **MR-2**: D2WebView の `htmlShell(for:)` で SVG から `<script>` / `<script ...>` タグとその内容を正規表現またはパーサーで除去するサニタイズ処理を追加する
* **MR-3**: ConfluenceService の `visitLink` / `visitImage` で URL を XML 属性としてエスケープする（`&` → `&amp;`、`"` → `&quot;`、`<` → `&lt;`、`>` → `&gt;`）
* **MR-4**: ConfluenceService の `visitLink` / `visitImage` で **`javascript:` スキームの URL のみ**ブロックする（空文字列に置換、またはリンクテキストのみ出力）

  **MR-4 スコープに関する重要な明確化（2026-05-04 人間レビューによる）**:
  - 本タスクでブロックするスキームは **`javascript:` のみ**
  - **`data:` および `vbscript:` はスコープ外**。これらは正当な用途（例: `data:image/png;base64,...` のインライン画像）を持つため、本 PR では一律ブロックしない
  - もし将来的に `data:` / `vbscript:` 対策が必要になった場合は、MIME ホワイトリスト方式など副作用のない設計を別 issue で議論する

### オプション要件

* **OR-1**: WKWebView の `WKContentRuleListStore` を使い、`javascript:` スキームへのナビゲーションをブラウザレベルでブロックする（Defense in Depth）
* **OR-2**: D2WebView でイベントハンドラ属性（`onload`, `onerror` 等）も SVG から除去する
* **OR-3**: DiffView.swift（同様に `loadHTMLString` を使用）のサニタイズ状況を監査し、必要なら同等の対策を適用する

## 4. 非機能要件

### パフォーマンス

* `callAsyncJavaScript` への移行でプレビュー更新のレイテンシが現行（`evaluateJavaScript`）と比較して有意に増加しないこと（体感 100ms 以内の差）
* SVG サニタイズ処理が 1MB の SVG に対して 50ms 以内で完了すること

### アクセシビリティ

* 変更なし（本タスクはレンダリングの安全性改善であり、UI 変更を含まない）

### macOS との整合性

* `callAsyncJavaScript` は macOS 11+ で利用可能。kobaamd の最低要件は macOS 14 なので問題なし
* WKWebView の API は Apple の推奨パターンに沿って使用する

## 5. UI/UX

本タスクは内部のセキュリティ修正であり、ユーザー向け UI 変更はない。

### 影響するビュー構成（変更なし、動作確認対象）

```
+---------------------------------------------------+
| MainWindowView                                     |
| +--------+-------------------+-------------------+ |
| |Sidebar | EditorView        | PreviewView       | |
| |        |                   | +---------------+ | |
| |        |                   | |MarkdownWebView| | |  ← MR-1: injectBody 修正
| |        |                   | +---------------+ | |
| |        |                   | +---------------+ | |
| |        |                   | | D2WebView     | | |  ← MR-2: SVG サニタイズ
| |        |                   | +---------------+ | |
| +--------+-------------------+-------------------+ |
+---------------------------------------------------+

ConfluenceService は UI を持たない。                       ← MR-3, MR-4: URL エスケープ + javascript: ブロック
エクスポート結果は Confluence 側で確認。
```

各ビューの SwiftUI 階層:

* `PreviewView` → `MarkdownWebView`（NSViewRepresentable）: bodyHTML の差分注入
* `PreviewView` → `D2WebView`（NSViewRepresentable）: SVG の HTML シェル生成
* `ConfluenceService` は `StorageFormatWalker`（MarkupWalker）経由で HTML 文字列を生成

## 6. 受け入れ条件 (Acceptance Criteria)

- [x] **AC-1**: バッククォート 3 連（` ``` `）を含む Markdown がプレビューで正常にレンダリングされる（コードブロックとして表示、JS エラーなし）
- [x] **AC-2**: `<script>alert('xss')</script>` を含む SVG 文字列を D2WebView に渡した場合、`<script>` タグが除去され、アラートが表示されないこと
- [x] **AC-3**: ConfluenceService で `javascript:alert(1)` を dest に持つリンクをエクスポートした場合、出力 HTML に `javascript:` スキームが含まれないこと
- [x] **AC-4**: ConfluenceService で `"onmouseover="alert(1)` を dest に持つリンクをエクスポートした場合、`"` が `&quot;` にエスケープされ属性値が脱出しないこと
- [x] **AC-5**: ConfluenceService で `"onerror="alert(1)` を src に持つ画像をエクスポートした場合、同様にエスケープされること
- [x] **AC-6**: MarkdownWebView の `injectBody` で手動エスケープ（`replacingOccurrences` 3 行）が削除され、`callAsyncJavaScript` のパラメータバインディングが使用されていること（コードレビューで確認）
- [x] **AC-7**: Mermaid ダイアグラムを含む Markdown のプレビューが修正後も正常に動作すること（回帰確認）
- [x] **AC-8**（追加）: ConfluenceService で `data:image/png;base64,...` を src に持つ画像をエクスポートした場合、**そのまま `<ri:url ri:value="data:image/png;base64,..."/>` として出力される**こと（黙って空にしない）
- [x] **AC-9**（追加）: ConfluenceService で `vbscript:msgbox(1)` を dest に持つリンクをエクスポートした場合、**そのまま `<a href="vbscript:msgbox(1)">label</a>` として出力される**こと（MR-4 スコープ外）

## 7. テスト戦略

### 単体テスト

| 対象ファイル | テストファイル | テスト内容 |
| -- | -- | -- |
| `Sources/Services/ConfluenceService.swift` | `Tests/kobaamdTests/ConfluenceServiceXSSTests.swift` | `convertToStorageFormat` に `javascript:` URL（ブロック）/ `data:` URL（通過）/ `vbscript:` URL（通過）/ `"` を含む URL（エスケープ）/ 通常 URL を渡し、出力 HTML を検証 |
| `Sources/Views/Preview/D2WebView.swift` | `Tests/kobaamdTests/D2SanitizeTests.swift` | SVG サニタイズ関数に `<script>` 含み SVG を渡し、出力に `<script>` が残らないことを検証 |

### 手動確認

1. **MarkdownWebView 回帰テスト**:
   * バッククォートを含む Markdown（コードフェンス内にバッククォート）を入力し、プレビューが崩れないことを確認
   * `$` 記号を含む Markdown（LaTeX 風記法）が正常表示されることを確認
   * Mermaid コードブロックがプレビューで描画されることを確認
   * エディタでカーソルを移動し、プレビューのハイライト追従が動作することを確認
2. **D2WebView 確認**:
   * D2 ダイアグラムが含まれる Markdown を開き、SVG がプレビューに正常表示されることを確認
   * パン・ズームが動作することを確認
3. **Confluence エクスポート確認**（Confluence 環境がある場合）:
   * リンクと画像を含む Markdown をエクスポートし、Confluence 上で正常表示されることを確認
   * data URI インライン画像（`![alt](data:image/png;base64,...)`）が Confluence 上で画像として表示されることを確認

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
| -- | -- | -- |
| `Sources/Views/Preview/MarkdownWebView.swift` | 変更 | `injectBody` メソッドを `callAsyncJavaScript` ベースに書き換え。手動エスケープ 3 行を削除 |
| `Sources/Views/Preview/D2WebView.swift` | 変更 | `htmlShell(for:)` に SVG サニタイズ処理を追加 |
| `Sources/Services/ConfluenceService.swift` | 変更 | `StorageFormatWalker` の `visitLink` / `visitImage` に URL エスケープ・スキーム検証を追加。`sanitizeURL` は `javascript:` のみブロック |

**共有コンテナへの注意**:

* `MarkdownWebView` は `PreviewView.swift` から使用。`shellHTML` / `bodyHTML` の型・インターフェースは変更しない（内部実装のみ変更）
* `ConfluenceService` の `StorageFormatWalker` は private struct。`convertToStorageFormat` の公開 API シグネチャは変更なし
* `D2WebView` は `PreviewView.swift` から使用。`svg: String` のインターフェースは変更なし

**変更してはいけない箇所**（rework 後の更新含む）:

* `sanitizeURL` のブロック対象を `javascript:` 以外に拡大しない（`data:` / `vbscript:` 等は通過させる）
* `escapeXMLAttribute` のエスケープ対象（`& " ' < >`）はそのまま維持
* `visitLink` / `visitImage` の HTML 出力構造（`<a>` 要素・`<ac:image>` 要素の形式）は変更しない

### その他リスク

* **既存コードへの影響**: `callAsyncJavaScript` は `evaluateJavaScript` と異なり Promise ベース。Coordinator の `webView(_:didFinish:)` 内の `evaluateJavaScript` も同様に移行するか検討が必要（ただしそちらは数値リテラルのみなので脆弱性はない）
* **互換性**: `callAsyncJavaScript` は macOS 11+ だが、kobaamd の最低要件 macOS 14 なので問題なし
* **外部依存**: D2 CLI の SVG 出力形式に依存。D2 バージョンアップで SVG 構造が変わった場合、サニタイズの正規表現が機能しない可能性がある。パーサーベースのサニタイズが望ましいが、正規表現でも `<script` タグの除去は十分実用的
* **WYSIWYGEditorView.swift**: 同ファイルも `evaluateJavaScript` を使用しているが、`_setContent` に JSON エンコード済みの値を渡しており（76 行目）、本タスクのスコープ外。ただし監査推奨

## 9. 計測・成果指標

セキュリティ修正のため、定量的な成果指標は定義しない。以下を定性的に確認する:

* 修正後、既知の 3 つの XSS ベクターが再現しないこと
* プレビューの描画パフォーマンスに体感劣化がないこと

リリース後評価のため、パフォーマンスの定量計測は未定義。

## 10. 参考資料

* [Apple Developer: callAsyncJavaScript(_:arguments:in:contentWorld:)](https://developer.apple.com/documentation/webkit/wkwebview/3656441-callasyncjavascript) — パラメータバインディングによる安全な JS 実行
* [Apple Developer: WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore) — コンテンツルールによる Defense in Depth
* [OWASP: XSS Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Scripting_Prevention_Cheat_Sheet.html)
* [CWE-79: Improper Neutralization of Input During Web Page Generation](https://cwe.mitre.org/data/definitions/79.html)
* [SVG Security: Script injection via SVG](https://owasp.org/www-community/xss-filter-evasion-cheatsheet) — SVG 内スクリプト注入パターン
