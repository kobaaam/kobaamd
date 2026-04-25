# kobaamd

**A lightweight, Mac-native Markdown editor.**
**軽量な、Mac ネイティブの Markdown エディタ。**

---

## Motivation / なぜ作ったか

I wanted a simple, fast Markdown editor that felt at home on macOS — one that opens a folder, shows files, and gets out of the way. Nothing more, nothing less.

シンプルで軽快な Markdown エディタが欲しかった。フォルダを開いて、ファイルを一覧して、あとは邪魔しない。それだけのツールを、Mac らしい質感で作りたかった。

---

## Features / 機能

- **Instant preview / リアルタイムプレビュー** — Split view or WYSIWYG mode / スプリットビューまたは WYSIWYG モード
- **Folder workspace / フォルダワークスペース** — Open a folder and browse all files in a sidebar / フォルダを開いてサイドバーでファイルを管理
- **Mermaid diagrams / Mermaid ダイアグラム** — Flowcharts, sequence diagrams, Gantt charts rendered inline / フローチャート・シーケンス図・ガントチャートをインラインで描画
- **Tabbed editing / タブ編集** — Multiple files open simultaneously (⌘T) / 複数ファイルを同時に開く（⌘T）
- **Syntax highlighting / シンタックスハイライト** — Markdown syntax highlighted in the editor / エディタ内の Markdown 構文をハイライト
- **Full-text search / 全文検索** — Search across all files in your workspace / ワークスペース全ファイルを横断検索
- **Git panel / Git パネル** — View branch and status at a glance / ブランチ・差分をひと目で確認
- **AI assist / AI アシスト** — Send selected text to OpenAI / Anthropic / Gemini / 選択テキストを AI API に送信
- **Autosave / オートセーブ** — Changes saved automatically; manual save with ⌘S / 自動保存対応、⌘S で手動保存も可
- **macOS native** — SwiftUI + AppKit, macOS 14+, Apple Silicon optimized / SwiftUI + AppKit、Apple Silicon 最適化
- **Offline-first / オフライン優先** — Mermaid.js and EasyMDE bundled, no CDN required / Mermaid.js・EasyMDE をバンドル

---

## Requirements / 動作環境

- macOS 14 (Sonoma) or later / macOS 14（Sonoma）以降
- Apple Silicon (arm64) — Intel untested / Apple Silicon 推奨（Intel 未検証）

---

## Build / ビルド

kobaamd uses Swift Package Manager. No Xcode project required.
Swift Package Manager を使用します。Xcode プロジェクト不要。

```bash
# Clone / クローン
git clone https://github.com/kobaaam/kobaamd.git
cd kobaamd

# Build / ビルド
swift build

# Bundle into .app (copies binary + resources + app icon)
# .app バンドルを作成（バイナリ・リソース・アイコンをコピー）
./scripts/post-build.sh

# Launch / 起動
open .build/kobaamd.app
```

### Release build / リリースビルド

```bash
swift build -c release
./scripts/post-build.sh release
open .build/kobaamd.app
```

### Set as default Markdown editor / デフォルトの Markdown エディタに設定

After launching once, open any `.md` file in Finder → **Get Info (⌘I)** → "Open With" → select **kobaamd** → **"Change All…"**

一度起動後、Finder で `.md` ファイルを右クリック → **「情報を見る（⌘I）」** → 「このアプリケーションで開く」→ **kobaamd** を選択 → **「すべてを変更...」**

---

## Architecture / アーキテクチャ

```
kobaamd/
├── Sources/
│   ├── App/                    # Entry point, AppViewModel, commands
│   │                           # エントリポイント・グローバル状態・コマンド
│   ├── Models/                 # FileNode, EditorTab
│   ├── Views/
│   │   ├── MainWindowView.swift   # 3-pane layout (sidebar / editor / preview)
│   │   ├── Sidebar/               # FileTreeView, SearchView
│   │   ├── Editor/                # NSTextView wrapper, TabBarView, FindReplaceBar
│   │   ├── Preview/               # WKWebView-based Markdown renderer
│   │   ├── Git/                   # GitPanel
│   │   └── AI/                    # AI assist panel
│   ├── ViewModels/             # @Observable state — FileTree, Preview, Editor, Git
│   ├── Services/               # FileService, MarkdownService, AIService, GitService
│   └── Resources/              # mermaid.min.js, easymde, AppIcon.icns
├── scripts/
│   └── post-build.sh           # Bundles binary + resources → .app
├── Info.plist                  # App metadata + document type registration
└── Package.swift
```

**Stack:** SwiftUI + AppKit · MVVM (`@Observable`) · `swift-markdown` (Apple) · WKWebView · Mermaid.js

---

## Keyboard Shortcuts / キーボードショートカット

| Shortcut | Action / アクション |
|----------|---------------------|
| ⌘O | Open folder / フォルダを開く |
| ⌘N | New file / 新規ファイル |
| ⌘T | New tab / 新しいタブ |
| ⌘W | Close tab / タブを閉じる |
| ⌘S | Save / 保存 |
| ⌘F | Find & Replace / 検索・置換 |
| ⌘B | Toggle sidebar / サイドバー表示切替 |
| ⌘G | Toggle Git panel / Git パネル表示切替 |
| ⌘E | AI assist / AI アシスト |
| ⌘, | Settings / 設定 |

---

## Roadmap / ロードマップ

- [ ] **Rendered Markdown diff viewer** — See diffs as formatted Markdown, not raw syntax / レンダリング済み Markdown の差分ビューア

- [ ] **TreeSitter syntax highlighting** — Full language support in code blocks / コードブロックの完全な言語サポート

- [ ] **Export** — PDF, HTML export / PDF・HTML エクスポート

- [ ] **Outline panel** — Navigate headings / 見出しナビゲーション

- [ ] **Custom themes** — Light/dark/custom color schemes / カスタムカラーテーマ

---

## Contributing / コントリビュート

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
貢献を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

---

## License / ライセンス

MIT — see [LICENSE](LICENSE).
