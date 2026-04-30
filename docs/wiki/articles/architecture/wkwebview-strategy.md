---
title: WKWebView 共存戦略とメモリ管理
category: architecture
tags: [wkwebview, mermaid, d2, markdown-preview, memory, performance]
sources: [docs/adr/0004-mermaid-wkwebview.md, docs/adr/0011-d2-diagram-preview.md]
created: 2026-04-30
updated: 2026-04-30
---

# WKWebView 共存戦略とメモリ管理

## Summary

kobaamd は最大4つの WKWebView インスタンス（Markdown Preview / Mermaid 埋め込み / D2 / WYSIWYG）を使い分けている。すべて JS ライブラリをバンドルしオフライン動作を保証する設計だが、WKWebView のメモリコストが 100MB 目標に直接影響するため、遅延生成・差分更新・シェル再利用の3戦略で制御している。

## Content

### 4つの WKWebView とその役割

| WebView | ファイル | 用途 | 生成タイミング |
|---------|----------|------|----------------|
| **MarkdownWebView** | `Sources/Views/Preview/MarkdownWebView.swift` | Markdown プレビュー + Mermaid 埋め込み描画 | コンテンツが非空になった時点（遅延生成） |
| **MermaidWebView** | `Sources/Views/Preview/MermaidWebView.swift` | スタブ（現在は未使用、Mermaid は MarkdownWebView に統合済み） |
| **D2WebView** | `Sources/Views/Preview/D2WebView.swift` | D2 ダイアグラムの SVG 表示 + パン/ズーム | `.d2` ファイル選択時のみ |
| **WYSIWYGEditorView** | `Sources/Views/Editor/WYSIWYGEditorView.swift` | EasyMDE ベースの WYSIWYG エディタ | WYSIWYG モード切替時 |

実際に同時に存在する WebView は最大2つ（エディタ + プレビュー）。D2 プレビューと Markdown プレビューは排他的に切り替わり、WYSIWYG モードは通常のエディタと排他である。

### JS ライブラリのバンドル戦略

`BundledJS` 列挙型（`Sources/Services/BundledJS.swift`）が `Bundle.module` からの読み込みを一元管理する。

```swift
enum BundledJS {
    static let mermaid: String    = content(named: "mermaid.min.js")
    static let easymdeJS: String  = content(named: "easymde.min.js")
    static let easymdeCss: String = content(named: "easymde.min.css")
    static let svgPanZoom: String = content(named: "svg-pan-zoom.min.js")
}
```

**設計方針**:
- **オフラインファースト**: すべての JS/CSS はアプリバンドルに同梱し、CDN 依存をゼロにする
- **フォールバック**: バンドルリソースが見つからない場合（ビルドエラー等）は空文字列を返し、HTML テンプレート側が CDN URL にフォールバックする
- **遅延ロード**: `static let` で初回アクセス時に1回だけファイルを読み込み、以降はキャッシュされる

| ライブラリ | サイズ目安 | 使用箇所 |
|-----------|-----------|----------|
| mermaid.min.js | ~2.5MB | MarkdownWebView（シェル HTML に埋め込み） |
| easymde.min.js | ~300KB | WYSIWYGEditorView |
| easymde.min.css | ~30KB | WYSIWYGEditorView |
| svg-pan-zoom.min.js | ~30KB | D2WebView |

### HTML テンプレート生成パターン

各 WebView は異なるテンプレート生成パターンを採用している。

#### MarkdownWebView: シェル + 差分更新パターン

最も複雑な構成。`MarkdownService.toHTML()` がフル HTML（シェル）を、`toBodyHTML()` がボディのみを生成する。

1. **初回ロード**: `loadHTMLString(shellHTML)` でフル HTML をロード。シェルには `<style>`（テーマ CSS）と `<script>`（mermaid.min.js + 初期化コード）が含まれる
2. **差分更新**: `evaluateJavaScript` で `document.body.innerHTML` を差し替え。ページナビゲーションが発生しないため、WebView の再初期化コストを回避
3. **テーマ変更時**: シェルごと再ロード（CSS がシェルに埋め込まれているため）

```
初回: shellHTML (full page) → loadHTMLString
更新: bodyHTML (content only) → evaluateJavaScript で body.innerHTML 差し替え
テーマ変更: shellHTML 再生成 → loadHTMLString
```

#### D2WebView: フルリロードパターン

SVG 全体をインライン HTML として毎回 `loadHTMLString` で再ロードする。`Coordinator.lastSVG` で同一 SVG の重複ロードを防止。

- HTML シェルは `htmlShell(for:)` メソッドでインラインに生成
- `svg-pan-zoom.min.js` を `<script>` タグ内にインライン埋め込み
- トラックパッドのピンチズーム対応（`gesturestart`/`gesturechange`/`gestureend` イベント）

#### WYSIWYGEditorView: 静的テンプレート + 双方向同期パターン

HTML テンプレートはアプリ起動時に1回だけ生成される（`static let htmlTemplate`）。

- **Swift -> JS**: `evaluateJavaScript("_setContent(\(jsonStr))")` でコンテンツを push
- **JS -> Swift**: `WKScriptMessageHandler` 経由で `textChanged` メッセージを受信
- `_ignoreNext` フラグでエコーバック（Swift->JS->Swift の無限ループ）を防止
- EasyMDE の JS/CSS はバンドル優先、欠落時は `unpkg.com` CDN にフォールバック

### evaluateJavaScript の使い方と注意点

`evaluateJavaScript` は3つの目的で使用されている。

| 目的 | 使用箇所 | 注意点 |
|------|----------|--------|
| **DOM 差分更新** | MarkdownWebView.injectBody | body.innerHTML の全置換。Mermaid ブロックの再変換も同時に実行 |
| **スクロール同期** | MarkdownWebView.syncScroll, Coordinator.didFinish | エディタのスクロール位置をプレビューに反映 |
| **カーソル追従ハイライト** | Coordinator.highlightBySourceLine | `data-source-line-*` 属性を使ったブロック特定とスクロール |
| **コンテンツ push** | WYSIWYGEditorView.pushTextIfReady | JSON エンコードで特殊文字を安全にエスケープ |

**エスケープ戦略の差異**:
- MarkdownWebView: バックスラッシュ・バッククォート・`$` の手動エスケープ（テンプレートリテラル内に埋め込むため）
- WYSIWYGEditorView: `JSONEncoder` による安全なエスケープ（推奨パターン）

後者の JSON エンコードパターンのほうが堅牢であり、MarkdownWebView のエスケープも将来的に JSON 方式に統一することが望ましい。

### メモリ制約（100MB 目標）への影響

WKWebView は1インスタンスあたり約 30-50MB のメモリを消費する（WebKit プロセス含む）。100MB 目標の中で最大の消費者である。

**現在の対策**:

1. **遅延生成（Lazy Instantiation）**: `PreviewView` は `isReady` フラグで WebView の生成を遅延。コンテンツが空の状態では WebView を生成せず、約 50MB の節約になる
2. **排他的表示**: D2 プレビューと Markdown プレビューは `isD2File` で排他切替。同時に2つのプレビュー WebView は存在しない
3. **差分更新**: MarkdownWebView はページナビゲーションなしで `body.innerHTML` だけを更新。WebView の再生成を避けることでメモリのチャーンを抑制
4. **デバウンス**: `PreviewViewModel` は 300ms のデバウンスで連続入力時の不要な再レンダリングを抑制
5. **バックグラウンドレンダリング**: Markdown の HTML 変換は `Task.detached` でバックグラウンドスレッドに逃がし、メインスレッドの応答性を維持

### パフォーマンス上の考慮事項

| 項目 | 現状 | リスク |
|------|------|--------|
| mermaid.min.js のサイズ | ~2.5MB をシェル HTML にインライン埋め込み | 初回ロード時のパース時間。差分更新時は再ロードされない |
| WebKit プロセスの分離 | macOS の WKWebView はプロセス外で動作 | メモリ使用量が Activity Monitor 上で分散表示される |
| `loadHTMLString` の baseURL | `https://kobaamd-preview.local/` | ローカルファイルへの相対パスが解決されない（画像表示等に影響） |
| Mermaid 再変換 | 差分更新のたびに DOM を走査して `pre>code.language-mermaid` を `div.mermaid` に変換 | 大量のダイアグラムがある文書では遅延の可能性 |
| `PerfLogger` | シェルロードの開始/終了を計測 | 差分更新のパフォーマンスは未計測 |

### 将来の改善候補

- **WebView プールの導入**: 同種の WebView を使い回すことで初期化コストを削減
- **Mermaid の選択的ロード**: ダイアグラムを含まない文書では mermaid.min.js のロードをスキップ
- **evaluateJavaScript のエスケープ統一**: 全箇所で JSON エンコード方式に統一
- **baseURL のローカルファイル対応**: `WKURLSchemeHandler` でローカル画像を解決

## Related

- [[appkit-swiftui-bridge]] -- NSViewRepresentable パターンの基礎
- [[editor-core]] -- エディタ側の NSTextView 実装

## Sources

- `docs/adr/0004-mermaid-wkwebview.md` -- Mermaid.js + WKWebView 採用の意思決定
- `Sources/Views/Preview/MarkdownWebView.swift` -- Markdown プレビューの WebView 実装
- `Sources/Views/Preview/D2WebView.swift` -- D2 ダイアグラムの WebView 実装
- `Sources/Views/Editor/WYSIWYGEditorView.swift` -- WYSIWYG エディタの WebView 実装
- `Sources/Services/BundledJS.swift` -- JS/CSS バンドル管理
- `Sources/Services/MarkdownService.swift` -- HTML テンプレート生成
