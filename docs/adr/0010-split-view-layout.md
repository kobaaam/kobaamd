# ADR-0010: Split View レイアウト方式

- **Status**: accepted
- **Date**: 2025-12
- **Deciders**: 人間 / Claude / Codex
- **Related**: ADR-0002

## Context

kobaamd は Markdown エディタとして「サイドバー | エディタ | プレビュー」の3ペイン構成を必要とする。加えて、右端に AI チャットサイドバーを表示する4ペイン目も想定される。

macOS 標準の `NavigationSplitView` は列数が2〜3に制限され、各列の幅制御やドラッグリサイズの自由度が低い。SwiftUI 標準の `HSplitView` はペインの最小幅制御やカスタムディバイダーの実装が困難で、デザイントークン（`Color.kobaLine` 等）との統合が難しい。

求められる要件:

1. サイドバーはトグルで表示/非表示（固定幅 240pt）
2. エディタとプレビューの分割比率をドラッグで自由に変更可能
3. AI チャットサイドバーは右端にトグル表示（固定幅 320pt）
4. プレビューモード（エディタのみ / スプリット / WYSIWYG）の動的切り替え
5. 各ペイン間のディバイダーはアプリ全体のデザイントークンに統一

## Decision

**SwiftUI `HStack` + `GeometryReader` + カスタムディバイダーによる完全カスタムレイアウト**を採用した。

### 具体的な実装構成

最上位の `MainWindowView.body` で `HStack(spacing: 0)` を使い、以下の順でペインを配置:

```
HStack(spacing: 0) {
    [SidebarView (240pt, 条件付き表示)]
    [KobaDivider (1px)]
    [VStack: TabBar + エディタ/プレビュー領域 (残り全幅)]
    [KobaDivider (1px, 条件付き表示)]
    [AIChatView (320pt, 条件付き表示)]
}
```

エディタ/プレビューのスプリット表示は、`GeometryReader` で利用可能幅を取得し、`@State splitFraction: CGFloat` (初期値 0.55) に基づいてエディタ幅を `geo.size.width * splitFraction` で計算する。

ドラッグリサイズは `SplitDivider` カスタム View で実装:

- `DragGesture` でドラッグ量を検出し `fraction` を 0.2〜0.8 の範囲にクランプ
- `NSCursor.resizeLeftRight` でカーソルをリサイズアイコンに変更
- ディバイダーは 1px の `Color.kobaLine` + 左右 3px のパディングでヒットエリアを確保

サイドバー・AI チャットの表示切替は `Bool` フラグ + `.transition(.move(edge:))` + `.animation(.easeInOut(duration: 0.2))` で制御。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| NavigationSplitView | Apple 推奨・アクセシビリティ標準対応 | 列数制限(2〜3)、幅の自由度が低い、4ペイン不可 | AI チャット含む4ペイン構成に対応できない |
| HSplitView (標準) | 宣言的でコード量が少ない | カスタムディバイダー不可、最小幅制御が不安定、デザイントークン統合困難 | デザイン要件を満たせない |
| NSSplitViewController (AppKit) | 最も柔軟・安定 | SwiftUI との統合コストが高い、Representable ラッパーが複雑化 | エディタ部分で既に AppKit ラップ (NSTextView) を使っており、レイアウト層まで AppKit にするとメンテコストが過大 |

## Consequences

### Positive
- 4ペイン構成（サイドバー・エディタ・プレビュー・AI チャット）を自然に実現
- ペインの表示/非表示をアニメーション付きで柔軟に切り替え可能
- ディバイダーのデザインをアプリ全体のトークン (`Color.kobaLine`) に統一
- `splitFraction` によるエディタ/プレビュー比率の直感的な制御（0.2〜0.8）
- プレビューモード切替（off / split / wysiwyg）を同一 VStack 内の条件分岐で簡潔に実装

### Negative
- `GeometryReader` 依存によりレイアウト再計算が頻繁に発生する可能性
- アクセシビリティ（VoiceOver でのペイン認識・ディバイダー操作）は手動で対応が必要
- ウィンドウリサイズ時の `splitFraction` 保持は実装済みだが、ウィンドウサイズが極端に小さい場合の `max(280, ...)` クランプに依存

### Risks
- macOS の将来バージョンで `GeometryReader` の挙動が変わった場合、レイアウト崩れのリスク
- ペイン数がさらに増えた場合（例: ターミナルペイン）、`HStack` のネストが深くなり可読性が低下する可能性

## References

- `Sources/Views/MainWindowView.swift` — レイアウト最上位・`SplitDivider` 定義
- `Sources/Views/Sidebar/SidebarView.swift` — サイドバー内部構成
- `Sources/Views/Editor/EditorView.swift` — エディタ領域
- `Sources/Views/Preview/PreviewView.swift` — プレビュー領域
- ADR-0002: NSTextView AppKit ラップ（エディタ層の AppKit 依存に関連）
