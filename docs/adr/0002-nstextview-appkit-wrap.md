# ADR-0002: NSTextView AppKit ラップによるエディタ実装

- **Status**: accepted
- **Date**: 2025-12-01
- **Deciders**: 人間
- **Related**: ADR-0001

## Context

Markdown エディタの中核であるテキスト編集コンポーネントの選定。SwiftUI の `TextEditor` では行番号表示、シンタックスハイライト、高度なテキスト操作が困難。

## Decision

**NSTextView を NSViewRepresentable でラップ**して SwiftUI に統合する。

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| SwiftUI TextEditor | 実装が簡単 | カスタマイズ不可、行番号非対応 | 機能不足 |
| WKWebView + CodeMirror | Web エコシステム活用 | ネイティブ感の喪失、IME 問題 | macOS ネイティブ体験を重視 |
| SourceEditor (Xcode内部) | 高機能 | プライベート API、App Store 不可 | 配布制約 |

## Consequences

### Positive
- macOS ネイティブのテキスト編集体験（IME、スクロール、アクセシビリティ）
- NSTextStorage による高度なシンタックスハイライト制御
- 行番号、Find/Replace、インデント制御が自由に実装可能

### Negative
- SwiftUI との橋渡しコードが複雑（NSViewRepresentable + Coordinator）
- macOS バージョン間の挙動差異（macOS 26 不可視バグ: feedback_nstextview_macos26.md 参照）

### Risks
- AppKit 非推奨化の長期リスク（ただし Apple は当面維持の姿勢）

## References

- Apple: NSTextView Class Reference
- docs/learnings/ — NSTextView macOS 26 不可視バグ修正
