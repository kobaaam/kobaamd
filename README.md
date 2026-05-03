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
- **Folder workspace / フォルダワークスペース** — File tree, outline, and TODO panel in a VS Code-style sidebar / VS Code 風サイドバーにファイルツリー・アウトライン・TODO を常時表示
- **Mermaid diagrams / Mermaid ダイアグラム** — Flowcharts, sequence diagrams, Gantt charts rendered inline / フローチャート・シーケンス図・ガントチャートをインラインで描画
- **D2 diagrams / D2 ダイアグラム** — D2 diagram preview rendered in the preview pane / D2 図をプレビューペインでレンダリング
- **Tabbed editing / タブ編集** — Multiple files open simultaneously (⌘T) / 複数ファイルを同時に開く（⌘T）
- **Syntax highlighting / シンタックスハイライト** — Markdown syntax highlighted in the editor / エディタ内の Markdown 構文をハイライト
- **Full-text search / 全文検索** — Search across all files in your workspace / ワークスペース全ファイルを横断検索
- **Outline panel / アウトラインパネル** — Navigate headings (H1–H6) with editor + preview sync / 見出し一覧からエディタ・プレビューを同期ジャンプ
- **AI assist / AI アシスト** — Send selected text to OpenAI / Anthropic / Gemini / 選択テキストを AI API に送信
- **AI chat sidebar / AI チャットサイドバー** — Multi-turn conversation with persistent context in a dedicated sidebar (⌘E) / 専用サイドバーで履歴を保ちながら AI とマルチターン会話（⌘E）
- **File templates / ファイルテンプレート** — AI-oriented presets for README, diary, meeting notes, and tech specs (⌘N picker) / AI フレンドリーな骨格を即挿入（⌘N ピッカー）
- **Color themes / カラーテーマ** — Built-in light, dark, solarized, and monokai themes for editor and preview / エディタ・プレビュー用ライト・ダーク・Solarized・Monokai テーマを内蔵
- **Rendered Markdown diff viewer / レンダリング済み Markdown 差分ビューア** — View AI-generated diffs as formatted Markdown with green/red highlights, not raw syntax (⌘⇧D to toggle) / AI 生成差分をレンダリング済み Markdown で緑・赤ハイライト表示（⌘⇧D でトグル）
- **In-app help / アプリ内ヘルプ** — Built-in help window with shortcuts, features, and troubleshooting (⌘?) / ショートカット・機能説明・トラブルシューティングをアプリ内で参照（⌘?）
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

# Set up git hooks (one-time) / git hooks の初期設定（初回のみ）
./scripts/hooks/install.sh

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
│   ├── Models/                 # FileNode, EditorTab, DocumentTemplate, ColorTheme
│   ├── Views/
│   │   ├── MainWindowView.swift   # 3-pane layout (sidebar / editor / preview)
│   │   ├── Sidebar/               # FileTreeView, SearchView, OutlineView
│   │   ├── Editor/                # NSTextView wrapper, TabBarView, FindReplaceBar, TemplatePickerView
│   │   ├── Diff/                  # DiffView, rendered Markdown diff (WKWebView-based)
│   │   ├── Help/                  # HelpWindowView, HelpContentView (in-app help)
│   │   ├── Preview/               # WKWebView-based Markdown + Mermaid + D2 renderer
│   │   └── AI/                    # AI assist panel, AIChatView (multi-turn chat)
│   ├── ViewModels/             # @Observable state — FileTree, Preview, Search, Outline, AIChatViewModel, DiffViewModel
│   ├── Services/               # FileService, MarkdownService, AIService, GitService
│   └── Resources/              # mermaid.min.js, easymde, AppIcon.icns, templates/ (AI presets)
├── scripts/
│   └── post-build.sh           # Bundles binary + resources → .app
├── Info.plist                  # App metadata + document type registration
└── Package.swift
```

**Stack:** SwiftUI + AppKit · MVVM (`@Observable`) · `swift-markdown` (Apple) · WKWebView · Mermaid.js · D2

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
| ⌘E | AI assist / AI アシスト |
| ⌘, | Settings / 設定 |
| ⌘? | Help / ヘルプ |

---

## Roadmap / ロードマップ

- [x] **Rendered Markdown diff viewer** — See diffs as formatted Markdown, not raw syntax / レンダリング済み Markdown の差分ビューア

- [ ] **TreeSitter syntax highlighting** — Full language support in code blocks / コードブロックの完全な言語サポート

- [ ] **Export** — PDF, HTML export / PDF・HTML エクスポート

- [x] **Custom themes** — Light/dark/custom color schemes / カスタムカラーテーマ

---

## Contributing / コントリビュート

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
貢献を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

---

## License / ライセンス

MIT — see [LICENSE](LICENSE).
