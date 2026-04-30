# ADR-0011: D2 ダイアグラムのローカルバイナリ + WKWebView プレビュー

- **Status**: accepted
- **Date**: 2026-01
- **Deciders**: 人間 / Claude / Codex
- **Related**: ADR-0004 (Mermaid.js + WKWebView)

## Context

kobaamd は ADR-0004 で Mermaid.js によるダイアグラムプレビューを実装済みだが、ユーザーから D2 言語のサポート要望があった。D2 は宣言的なダイアグラム言語で、Mermaid.js とは異なりブラウザ内 JS ランタイムが存在せず、ローカルにインストールされた `d2` CLI バイナリでコンパイルする必要がある。

技術的制約:

- D2 には公式の JavaScript / WASM ランタイムが提供されていない（Go 製）
- Mermaid.js のようにバンドル JS だけで完結する方式は取れない
- macOS ネイティブアプリとして、外部プロセス呼び出しのセキュリティとパフォーマンスを考慮する必要がある

## Decision

**ローカル `d2` バイナリを `Process` で呼び出し、生成された SVG を WKWebView で表示する方式**を採用した。

### 実装構成

| コンポーネント | ファイル | 責務 |
|---|---|---|
| `D2Service` | `Sources/Services/D2Service.swift` | d2 バイナリの検出・Process 経由の SVG レンダリング |
| `D2PreviewViewModel` | `Sources/ViewModels/D2PreviewViewModel.swift` | デバウンス付きレンダリング制御・状態管理 |
| `D2WebView` | `Sources/Views/Preview/D2WebView.swift` | SVG を HTML シェルに埋め込み WKWebView で表示 |

### D2Service の設計

- **バイナリ検出**: `/opt/homebrew/bin/d2`（Apple Silicon Homebrew）と `/usr/local/bin/d2`（Intel Homebrew）の 2 パスを候補として順に探索。`FileManager.fileExists` で存在確認する
- **レンダリング**: `Process` で `d2 -`（stdin 入力モード）を起動し、D2 ソースを stdin に書き込み、stdout から SVG を受け取る。`Task.detached(priority: .userInitiated)` でバックグラウンド実行し、メインスレッドをブロックしない
- **エラーハンドリング**: `D2Error.notInstalled`（バイナリ未検出）と `D2Error.renderFailed`（コンパイルエラー）の 2 種類。stderr の出力をエラーメッセージとしてユーザーに表示

### D2PreviewViewModel の設計

- `@Observable` + `@MainActor` で SwiftUI と統合（ADR-0001 の MVVM パターンに準拠）
- **300ms デバウンス**: 入力のたびに `Task.sleep` で遅延させ、連続入力時の無駄な d2 プロセス起動を抑制。前回のタスクは `cancel()` で明示的にキャンセル
- `isRendering` / `errorMessage` で UI にレンダリング状態とエラーをバインド

### D2WebView の設計

- `NSViewRepresentable` で WKWebView をラップ（ADR-0004 の Mermaid プレビューと同じパターン）
- **Coordinator で差分検知**: `lastSVG` を保持し、SVG が変わらなければ `loadHTMLString` を呼ばない（不要な再描画を回避）
- **svg-pan-zoom**: `BundledJS.svgPanZoom` をバンドルし、ズーム・パン操作を提供。macOS トラックパッドのピンチジェスチャーにも `gesturestart` / `gesturechange` / `gestureend` イベントで対応
- SVG の `width` / `height` 属性を除去し `viewBox` に変換することで、ビューポートへのフィットを実現

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| D2 WASM ランタイム | 外部バイナリ不要、サンドボックス内で完結 | 公式 WASM ビルドが存在しない。非公式ビルドはメンテナンス不安 | 技術的に実現不可能（2026-01 時点） |
| サーバーサイドコンパイル | ユーザー環境に依存しない | ネットワーク必須、レイテンシ増加、サーバー運用コスト、プライバシー懸念 | オフライン動作を重視するネイティブアプリの方針と矛盾 |
| D2 非サポート（Mermaid のみ） | 実装コストゼロ、依存なし | D2 ユーザーの要望に応えられない | 「AIが生成したMarkdownを最も快適に扱える」ビジョンに反する |

## Consequences

### Positive

- Mermaid.js と並ぶ 2 つ目のダイアグラム言語をサポートし、エディタの表現力が向上
- ローカル実行のため、オフラインで完全に動作し、データがサーバーに送信されない
- ADR-0004 の WKWebView + svg-pan-zoom パターンを再利用しており、実装の一貫性が高い
- デバウンスとタスクキャンセルにより、リアルタイムプレビューでも CPU 負荷を抑制

### Negative

- ユーザーが事前に `brew install d2` する必要がある（ゼロコンフィグではない）
- `d2` バイナリのバージョン差異により、レンダリング結果が環境ごとに異なる可能性がある
- `Process` による外部プロセス呼び出しは App Sandbox と互換性がない（Mac App Store 配布時に制約）

### Risks

- D2 プロジェクトの開発停止やバイナリ配布方法の変更に追従が必要
- 巨大な D2 ダイアグラムでコンパイルが長時間かかる場合、タイムアウト機構が未実装（現在は `waitUntilExit` で無期限待機）
- Homebrew 以外のインストールパス（Nix, MacPorts 等）には未対応

## References

- [D2 公式サイト](https://d2lang.com/)
- [D2 GitHub リポジトリ](https://github.com/terrastruct/d2)
- ADR-0004: Mermaid.js + WKWebView によるダイアグラムレンダリング
