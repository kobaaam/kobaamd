# kobaamd アーキテクチャ設計

**Version**: 0.1
**Date**: 2026-04-20
**Author**: Claude (Architect) + Gemini (Tech Research)
**Status**: Draft

---

## 技術選定（確定）

| 領域 | 採用技術 | 理由 |
|------|---------|------|
| UIフレームワーク | SwiftUI + AppKit | macOSネイティブ |
| アーキテクチャ | MVVM (`@Observable`) | SwiftUI 5.0最適・学習コスト低 |
| エディタコア | `NSTextView` (AppKit ラップ) | シンタックスハイライト・行番号・将来的なdiff対応 |
| Markdownパーサー | `swift-markdown` (Apple製) | Swift Native・AST取得可・macOS 14最適 |
| シンタックスハイライト | `NSTextStorage` + 正規表現（v1）→ TreeSitter（v2） | 段階的に強化 |
| ダイアグラム | Mermaid.js（`WKWebView`経由） | プレビューのみ |
| AI連携 | REST API（OpenAI / Anthropic / Gemini） | プロバイダー非依存 |
| ファイル管理 | `FileManager` + `NSOpenPanel` | ローカルファイルのみ |

---

## レイヤー構成

```
┌─────────────────────────────────────────┐
│           Views (SwiftUI)               │
│  SidebarView / EditorView / PreviewView │
└──────────────┬──────────────────────────┘
               │ @Observable binding
┌──────────────▼──────────────────────────┐
│         ViewModels (@Observable)        │
│  AppViewModel / EditorViewModel /       │
│  FileTreeViewModel / PreviewViewModel   │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│            Services                     │
│  FileService / MarkdownService /        │
│  AIService / HighlightService           │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│             Models                      │
│  FileNode / Document / AIRequest        │
└─────────────────────────────────────────┘
```

---

## ディレクトリ構成（案）

```
kobaamd/
├── App/
│   ├── kobaamdApp.swift        # エントリポイント
│   └── AppViewModel.swift      # グローバル状態
├── Views/
│   ├── MainWindowView.swift    # 3ペイン構成
│   ├── Sidebar/
│   │   ├── SidebarView.swift
│   │   └── FileTreeView.swift
│   ├── Editor/
│   │   ├── EditorView.swift    # NSTextView ラッパー
│   │   └── NSTextViewWrapper.swift
│   └── Preview/
│       ├── PreviewView.swift
│       └── MermaidWebView.swift
├── ViewModels/
│   ├── FileTreeViewModel.swift
│   ├── EditorViewModel.swift
│   └── PreviewViewModel.swift
├── Services/
│   ├── FileService.swift       # ファイル読み書き・監視
│   ├── MarkdownService.swift   # swift-markdown パーシング
│   ├── HighlightService.swift  # シンタックスハイライト
│   └── AIService.swift         # AI REST API
└── Models/
    ├── FileNode.swift
    └── Document.swift
```

---

## データフロー

### 編集 → プレビュー
```
NSTextView (編集)
  → EditorViewModel (テキスト変更検知)
    → MarkdownService.parse() → AST
      → PreviewViewModel
        → PreviewView (WKWebView レンダリング)
```

### ファイルツリー
```
FileService (FileManager + FileSystemWatcher)
  → FileTreeViewModel
    → FileTreeView (List)
      → ユーザーがファイル選択
        → EditorViewModel.load(file)
```

### AI連携
```
EditorView (選択テキスト)
  → AIService.request(prompt, provider)
    → REST API (OpenAI / Anthropic / Gemini)
      → EditorViewModel.applyCompletion()
```

---

## v1.0 実装優先順位

| 優先度 | 機能 | 担当 |
|--------|------|------|
| 1 | プロジェクト構成・基本ウィンドウ | Codex |
| 2 | フォルダツリー + ファイル開閉 | Codex |
| 3 | NSTextView エディタ（基本） | Codex |
| 4 | swift-markdown リアルタイムプレビュー | Codex |
| 5 | シンタックスハイライト（正規表現ベース） | Codex |
| 6 | AI連携（選択テキスト → API） | Codex + Claude |
| 7 | 全文検索 | Codex |

---

## 未解決事項（Phase 0 TBD）

- [ ] プレビューモード: 2ペイン vs シームレス（デフォルト）
- [ ] AI APIキー管理: Keychain経由で保存する方針で固める
- [ ] WKWebViewをプレビューに使う場合のパフォーマンス検証
- [ ] TreeSitter Swift バインディングの選定（`tree-sitter-swift` / SwiftTreeSitter）
