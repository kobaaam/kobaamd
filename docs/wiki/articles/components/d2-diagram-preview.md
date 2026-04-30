---
title: D2 ダイアグラムプレビュー
category: components
tags: [d2, diagram, wkwebview, svg-pan-zoom]
sources: [docs/adr/0011-d2-diagram-preview.md]
created: 2026-04-30
updated: 2026-04-30
---

# D2 ダイアグラムプレビュー

## Summary

D2 言語で記述されたダイアグラムをリアルタイムプレビューするコンポーネント群。ローカルの `d2` CLI バイナリを Process API で呼び出して SVG を生成し、WKWebView + svg-pan-zoom.js でインタラクティブに表示する。Mermaid.js がブラウザ内レンダリングなのに対し、D2 は外部プロセス依存という設計上の違いがある。

## Content

### D2Service — コンパイルフロー

`D2Service` はローカルにインストールされた D2 バイナリを `Process` (Foundation) 経由で呼び出す薄いラッパー。

**バイナリ探索**: `/opt/homebrew/bin/d2`、`/usr/local/bin/d2` の順で存在チェックし、最初に見つかったパスを使用する。`isD2Installed()` で事前に利用可否を判定できる。

**レンダリングパイプライン**:

1. `Task.detached(priority: .userInitiated)` でバックグラウンドスレッドに退避
2. `Process` を生成し、引数 `["-"]` で stdin 入力モードを指定
3. stdin に D2 ソースコードを書き込み → close
4. `waitUntilExit()` で同期的にプロセス完了を待機
5. stdout から SVG 文字列を取得、stderr からエラーメッセージを取得
6. `terminationStatus != 0` の場合は `D2Error.renderFailed` を throw

**エラー型**: `D2Error` は `notInstalled`（バイナリ未検出）と `renderFailed(String)`（レンダリング失敗）の 2 ケース。`LocalizedError` に準拠し、ユーザー向けメッセージを提供する。

### D2WebView — WKWebView + svg-pan-zoom.js によるインタラクティブ表示

`D2WebView` は `NSViewRepresentable` でラップした `WKWebView`。SVG 文字列を受け取り、HTML シェルに埋め込んで表示する。

**差分ロードの最適化**: `Coordinator` が `lastSVG` を保持し、SVG が変化していない場合は `loadHTMLString` をスキップする。これにより、SwiftUI の再描画サイクルでの不要なリロードを防止する。

**HTML シェル構成**:

- CSS: `overflow: hidden` で WebView 自体のスクロールを無効化し、svg-pan-zoom に制御を委譲
- `BundledJS.svgPanZoom`: アプリバンドルに同梱した `svg-pan-zoom.min.js` をインライン展開（CDN 不要、オフライン動作可能）
- SVG を `<body>` 直下にインライン挿入

**svg-pan-zoom 設定**:

```javascript
svgPanZoom(svg, {
    zoomEnabled: true,
    controlIconsEnabled: true,  // UI コントロールアイコン表示
    fit: true,                  // 初期表示でビューポートにフィット
    center: true,               // 中央寄せ
    minZoom: 0.05,
    maxZoom: 20,
    mouseWheelZoomEnabled: true
});
```

初期化前に、D2 が出力する SVG に `viewBox` 属性がない場合は `width`/`height` 属性から自動補完し、固定サイズ属性を除去してレスポンシブ表示に対応する。

### トラックパッドピンチズーム対応

macOS の WKWebView ではトラックパッドのピンチジェスチャーが `gesturestart` / `gesturechange` / `gestureend` イベントとして発火する。デフォルトでは WebView 自体のズーム（`allowsMagnification`）と競合するため、以下の対策を行っている:

1. `webView.allowsMagnification = false` で WebView ネイティブのズームを無効化
2. `gesturechange` イベントで `e.scale` の差分比率（`e.scale / lastScale`）を算出
3. `panZoom.zoomAtPointBy(relativeScale, { x: e.clientX, y: e.clientY })` でピンチ中心点を基準にズーム
4. 全 gesture イベントで `e.preventDefault()` を呼び、デフォルト動作を抑制

この実装により、トラックパッドピンチでもマウスホイールでも svg-pan-zoom を通じた一貫したズーム体験を提供する。

### D2PreviewViewModel — ズーム状態管理とデバウンス

`D2PreviewViewModel` は `@Observable` + `@MainActor` で状態を管理する ViewModel。

**公開プロパティ**:

| プロパティ | 型 | 説明 |
|---|---|---|
| `svg` | `String` | レンダリング済み SVG（空文字 = 未レンダリング） |
| `errorMessage` | `String?` | D2 エラーメッセージ |
| `isRendering` | `Bool` | レンダリング中フラグ（ローディング UI 用） |

**デバウンス制御**: `update(text:)` が呼ばれるたびに前回の `debounceTask` をキャンセルし、300ms の遅延後にレンダリングを実行する。エディタでのタイピング中に D2 プロセスが大量起動するのを防止する。キャンセル時は `Task.isCancelled` チェックで状態更新をスキップする。

### Mermaid.js との設計差異

| 観点 | D2 | Mermaid.js |
|---|---|---|
| レンダリング | 外部プロセス（`d2` CLI） | ブラウザ内 JS |
| 依存 | `brew install d2` が必要 | アプリバンドル同梱（オフライン完結） |
| SVG 生成 | stdin/stdout パイプ | DOM 操作で直接生成 |
| パン/ズーム | svg-pan-zoom.js（共通） | svg-pan-zoom.js（共通） |
| デバウンス | 300ms（プロセス起動コスト考慮） | 同等 |
| エラーハンドリング | stderr パース | JS 例外キャッチ |

D2 はプロセス起動のオーバーヘッドがあるため、Mermaid よりレイテンシが高い。一方で D2 のレイアウトエンジン（dagre + ELK）は複雑なダイアグラムでの品質が高く、用途に応じた使い分けを想定している。

## Related

- [[エディタコア (NSTextViewWrapper)]]
- [[AppKit-SwiftUI ブリッジ]]

## Sources

- docs/adr/0011-d2-diagram-preview.md
- Sources/Services/D2Service.swift
- Sources/Views/Preview/D2WebView.swift
- Sources/ViewModels/D2PreviewViewModel.swift
- Sources/Services/BundledJS.swift
