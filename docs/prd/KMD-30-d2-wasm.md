# KMD-30 — D2 ダイアグラムの WASM 化（Process() 排除）

> Linear: https://linear.app/kobaan/issue/KMD-30
> 状態: In Progress
> ブランチ: `feature/KMD-30-d2-wasm`

## 1. 背景・目的

`.d2` ファイルのリアルタイムプレビューを `/opt/homebrew/bin/d2` バイナリへの `Process()` 経由呼び出し（`Sources/Services/D2Service.swift`）で実現しているが、以下の問題を抱える。

1. インストール負荷: `brew install d2` が必須で「DL して即試せる」体験を損ねる
2. App Sandbox 非対応: `Process()` は将来の MAS 配信・Hardened Runtime 完全対応（KMD-26 Phase 2）を阻害
3. インストールパス依存: `/opt/homebrew/bin/d2` と `/usr/local/bin/d2` のハードコード探索しかできない

本チケットは KMD-26 Phase 2 に相当し、D2 公式の WASM ビルド（`@terrastruct/d2`）を WKWebView 内で実行する全面置換。

## 2. 事前検証結果（実装着手前の必須調査）

| 項目 | 結果 |
|---|---|
| `npm view @terrastruct/d2` | 0.1.33（latest）、unpacked 59.8 MB、deps なし、MPL-2.0 |
| ブラウザターゲット提供 | あり（`dist/browser/index.js`、7.8 MB 単一ファイル） |
| WASM 取得 | **不要** — `dist/browser/index.js` は WASM を base64 で内蔵し `atob` でデコード後 `WebAssembly.instantiate()` する。`./d2.wasm` / `./wasm_exec.js` は内部の `Bf()` / `pf` から返される（外部 fetch なし） |
| 想定オーバーヘッド | 単一 JS バンドル 7.8 MB のみ追加（gzip 不要） |

→ **Go ソース自前ビルドは不要**。Phase 1 として `dist/browser/index.js` を `Sources/Resources/d2-browser.js` にコピーし、SPM `.process("Resources")` でバンドル同梱する。

## 3. 機能要件（必須）

* `Sources/Resources/d2-browser.js`: `@terrastruct/d2` 0.1.33 の browser バンドルを配置
* `Sources/Services/BundledJS.swift`: `static let d2BrowserJS` を追加
* `Sources/Views/Preview/D2WebView.swift`: 現状の `svg: String` 受け取り型から `d2Code: String` 受け取り型に再設計
  - HTML シェルに `<script type="module">` で d2-browser.js を inline 埋め込み（SPA として動かす。ESM 構文は `export` を捨てて `globalThis.D2Module = ...` 経由でアクセス可能にする）
  - `WKScriptMessageHandler` 経由で WKWebView から Swift に SVG 文字列 / エラーメッセージを返却
  - 既存の `sanitizeSVG`（`<script>`/`on*` 除去）を **WASM 出力 SVG にも適用** してから DOM 挿入
  - svgPanZoom + ピンチズームは引き続き SVG レンダリング後に適用
* `Sources/ViewModels/D2PreviewViewModel.swift`: `D2Service` 依存除去。`update(text:)` の 300ms debounce は維持。レンダリングは WKWebView に委譲し、結果は messageHandler で受信
  - WKWebView 側との結合は `D2WebView` 経由で、ViewModel の `pendingCode` を WKWebView が読み取り `evaluateJavaScript` する形にする
* `Sources/Services/D2Service.swift`: **削除**

## 4. 非機能要件

* 初回 WASM ロード: 2 秒以内（手動計測）
* 再レンダリング: 500 ms 以内
* 外部通信: なし（オフライン優先）
* baseURL: `https://kobaamd-preview.local/` 維持

## 5. UI/UX

D2 プレビューの SwiftUI 構造は変えない。`D2PreviewView` は `errorMessage` / `isRendering` / `svg`（→`pendingCode`）を観測。エラー時は赤テキスト表示。

## 6. 受け入れ条件 (AC)

- [ ] `brew install d2` 未実施環境で `.d2` ファイルが SVG 表示される
- [ ] `Sources/Services/D2Service.swift` が削除されている
- [ ] 標準 D2 構文 4 種（shapes / connections / sequence / classes）が SVG レンダリングされる
- [ ] svgPanZoom + ピンチズームが従来通り動作
- [ ] 構文エラー時に赤テキストでエラーメッセージ表示
- [ ] `swift build` が警告・エラーなしで完了
- [ ] ネットワーク未接続でも動作（オフライン優先）
- [ ] 既存テスト群が PASS（`D2SanitizeTests` の `sanitizeSVG` は引き続き呼べる API を維持）
- [ ] 新規 `D2WebViewTests` が PASS（最低限：ESM ローダ HTML 生成の smoke / sanitize 経路 / エラー JSON ペイロードのパース）

## 7. テスト戦略

* `D2SanitizeTests`: 現行のまま動かす（API 互換のために `D2WebView` から `sanitizeSVG` を残す）
* `D2WebViewTests`: HTML シェル生成・JSON エンコード・エラー文字列ハンドリングを単体テスト
* 手動: ビルド済み app を `open .build/kobaamd.app` で起動し、サンプル `.d2` ファイルで shapes/connections/sequence/classes を確認

## 8. 影響範囲マップ

| ファイル | 変更種別 | 備考 |
| --- | --- | --- |
| `Sources/Resources/d2-browser.js` | **追加** | 7.8 MB、`@terrastruct/d2@0.1.33` の browser バンドルそのまま |
| `Sources/Services/BundledJS.swift` | 変更 | `d2BrowserJS` lazy property 追加 |
| `Sources/Views/Preview/D2WebView.swift` | **大幅変更** | API を `svg:` → `d2Code:` に変更、WASM ローダ HTML 化、messageHandler 追加 |
| `Sources/ViewModels/D2PreviewViewModel.swift` | 変更 | `D2Service` 依存除去、WKWebView との連携に置換 |
| `Sources/Views/Preview/PreviewView.swift` | **変更（ローカル限定）** | `D2WebView(svg:)` の呼び出しを `D2WebView(d2Code:)` に変更し、エラー / svg 状態の出し分けを ViewModel 駆動に揃える |
| `Sources/Services/D2Service.swift` | **削除** | `Process()` を含む全コード除去 |
| `Tests/kobaamdTests/D2SanitizeTests.swift` | 変更（API 整合のみ） | `D2WebView(svg: "")` → 新初期化子に置換 |
| `Tests/kobaamdTests/D2WebViewTests.swift` | **追加** | HTML シェル / JSON / sanitize のスモーク |
| `Package.swift` | 確認 | `.process("Resources")` で `.js` 追加は変更不要（既存 mermaid.min.js と同じ） |

**変更してはいけない箇所**: `MarkdownWebView`、`PreviewViewModel`、Mermaid 関連処理（`mermaid.min.js` ロードや MarkdownWebView 内の mermaid.run）、`Sources/ViewModels/DiffViewModel.swift` の `Process()` 呼び出し（別チケット）。

### 実装結果（2026-05-05 追記）

- `swift build` および `swift build -c release` が警告ゼロで完了。SPM `.process("Resources")` で `d2-browser.js` が `kobaamd_kobaamd.bundle` に正しくコピーされる
- `swift test` のテストランナー（`xctest`）が CommandLineTools 環境に存在しないため、テストはビルド成功のみ確認。テスト実行は CI / Xcode 入りの環境に委ねる（既存の運用と同じ）
- リソースバンドルサイズ: **3,556 KB → 11,560 KB（+7.8 MB）**。閾値 30 MB に対して十分余裕があるため、gzip 圧縮は不要と判断
- macOS 14 の `callAsyncJavaScript` completion handler が `(Result<Any, Error>) -> Void` 単一引数版になっていたため、Codex 出力の `(_, error)` を Result 分岐に手動修正
- 想定外の追加変更はなし（PRD section 8 のマップ通り）

## 9. リスクと残課題

* **WKWebView の ESM ロード**: WKWebView は `<script type="module">` の inline ロードに対応している（macOS 14+）。ただし `import` 文があると baseURL からの解決が必要。本実装では「browser バンドル全体を `<script>` で生成して `globalThis.D2 = ...` の名前空間にぶら下げる」方式を採る
* **WASM の `WebAssembly.instantiate()`**: `https://kobaamd-preview.local/` ベース URL での実行は標準的なオリジン扱いで動作する。バンドル内に WASM が埋め込まれているため CORS は発生しない
* **アプリバンドルサイズ**: WASM バンドル 7.8 MB 増。許容範囲

## 10. 参考

- npm: https://www.npmjs.com/package/@terrastruct/d2
- KMD-26（Hardened Runtime 有効化 + Process() 排除準備）
- KMD-28（WKWebView XSS 対策・`sanitizeSVG` 導入）
