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
- **Folder workspace / フォルダワークスペース** — File tree, outline, tags, and TODO panel in a VS Code-style sidebar / VS Code 風サイドバーにファイルツリー・アウトライン・タグ・TODO を常時表示
- **Mermaid diagrams / Mermaid ダイアグラム** — Flowcharts, sequence diagrams, Gantt charts rendered inline / フローチャート・シーケンス図・ガントチャートをインラインで描画
- **D2 diagrams / D2 ダイアグラム** — D2 diagram preview rendered in the preview pane / D2 図をプレビューペインでレンダリング
- **Tabbed editing / タブ編集** — Multiple files open simultaneously (⌘T) / 複数ファイルを同時に開く（⌘T）
- **TreeSitter syntax highlighting / TreeSitter シンタックスハイライト** — Full language support in code blocks using Tree-sitter / Tree-sitter によるコードブロック内の完全な言語サポート
- **Full-text search / 全文検索** — Search across all files in your workspace / ワークスペース全ファイルを横断検索
- **Quick Open / クイックオープン** — Fuzzy file picker (⌘P) / ファジーファイルピッカー（⌘P）
- **Outline panel / アウトラインパネル** — Navigate headings (H1–H6) with editor + preview sync / 見出し一覧からエディタ・プレビューを同期ジャンプ
- **Tags sidebar / タグサイドバー** — Browse and filter notes by frontmatter tags / frontmatter タグでノートを一覧・フィルタリング
- **CSV table preview / CSV テーブルプレビュー** — View CSV files as formatted tables in the preview pane / CSVファイルをプレビューペインで整形テーブル表示
- **File templates / ファイルテンプレート** — Presets for README, diary, meeting notes, and tech specs (⌘⇧N) / README・日記・議事録・技術仕様の骨格を即挿入（⌘⇧N ピッカー）
- **Rendered Markdown diff viewer / レンダリング済み Markdown 差分ビューア** — View AI-generated diffs as formatted Markdown with green/red highlights, not raw syntax (⌘⇧D to toggle) / AI 生成差分をレンダリング済み Markdown で緑・赤ハイライト表示（⌘⇧D でトグル）
- **PDF export / PDF エクスポート** — Export the current file to PDF (⌘⇧P) / 現在のファイルを PDF に書き出し（⌘⇧P）
- **Chromium browser preview / Chromium ブラウザプレビュー** — Preview pages in a local Chromium instance for full browser fidelity / ローカル Chromium インスタンスでフルブラウザ相当のプレビュー
- **Wiki search index / Wiki 検索インデックス** — Workspace-wide full-text index with tag awareness / タグ対応のワークスペース横断全文インデックス
- **In-app help / アプリ内ヘルプ** — Built-in help window with shortcuts, features, and troubleshooting (⌘?) / ショートカット・機能説明・トラブルシューティングをアプリ内で参照（⌘?）
- **Autosave / オートセーブ** — Changes saved automatically; manual save with ⌘S / 自動保存対応、⌘S で手動保存も可
- **Frontmatter editor / Frontmatter エディタ** — Structured YAML/TOML frontmatter recognized and editable via a dedicated inline panel / YAML/TOML の frontmatter を認識し、専用インラインパネルで編集可能
- **Backlinks pane / Backlinks ペイン** — See which files link to or mention the current file; convert unlinked mentions to wikilinks / 現在のファイルを参照しているファイルを一覧表示し、unlinked mention を wikilink に変換可能
- **macOS native** — SwiftUI + AppKit, macOS 14+, Apple Silicon optimized / SwiftUI + AppKit、Apple Silicon 最適化
- **Offline-first / オフライン優先** — Mermaid.js and EasyMDE bundled, no CDN required / Mermaid.js・EasyMDE をバンドル

### E1 shell (Ghostty terminal integration)
### E1 シェル（Ghostty ターミナル統合）

kobaamd ships a second UI mode called **E1**: Session rail | Terminal | Viewer. The embedded terminal is powered by [Ghostty](https://ghostty.org) via [libghostty-spm](https://github.com/Lakr233/libghostty-spm) (MIT).

kobaamd には **E1** という第二の UI モードが搭載されています。Session rail | Terminal | Viewer レイアウトで、組み込みターミナルは [Ghostty](https://ghostty.org) を [libghostty-spm](https://github.com/Lakr233/libghostty-spm)（MIT）経由で利用しています。

In **Settings**, turn off **「E1 シェル」** to use the classic Markdown 3-pane layout. Restart the app after toggling.
**設定**で **「E1 シェル」** を OFF にすると従来の Markdown 3ペイン UI に戻ります。切り替え後はアプリを再起動してください。

### MCP server

kobaamd ships a built-in [Model Context Protocol](https://modelcontextprotocol.io/) server (`Sources/CLI/`) that exposes your vault to any MCP-compatible AI client (e.g. Claude Desktop).

kobaamd には、Vault を任意の MCP 対応 AI クライアント（Claude Desktop 等）に公開する組み込み MCP サーバー（`Sources/CLI/`）が搭載されています。

Available tools: `GetBacklinks`, `GetHeadings`, `GetTags`, `ListNotes`, `ReadNote`, `SearchNotes`

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

### Daily dev loop / 日常開発

macOS の Hardened Runtime では実行中バイナリの上書きができないため、コード変更のたびに**開発用インスタンス**の再起動は必要です。本番用アプリとは切り離して運用できます。

| 用途 | バンドル | プロセス名 | Bundle ID |
|------|----------|------------|-----------|
| 日常利用（安定版） | `/Applications/kobaamd.app` | `kobaamd` | `com.kobaamd.app` |
| 開発・検証 | `.build/kobaamd-dev.app` | `kobaamd-dev` | `com.kobaamd.app.dev` |

`dev-run.sh` は **開発用だけ** ビルド→再起動します。`/Applications/kobaamd.app` は止まりません。設定・タブは Bundle ID ごとに別管理です（API キーは Keychain サービス名が共通のため共有されます）。

```bash
# 開発用を1回ビルドして起動（本番 kobaamd はそのまま）
./scripts/dev-run.sh

# 保存を監視して開発用だけ自動リロード（初回: brew install fswatch）
./scripts/dev-run.sh --watch

# 手動で開発バンドルだけ作る場合
swift build && ./scripts/post-build.sh debug dev && open .build/kobaamd-dev.app
```

If local ad-hoc rebuilds cause repeated Keychain prompts after saving API keys, run the development ACL helper described in [`docs/dev-keychain-acl.md`](docs/dev-keychain-acl.md).
ローカルの ad-hoc 再ビルド後に API キーの Keychain アクセス確認が繰り返される場合は、[`docs/dev-keychain-acl.md`](docs/dev-keychain-acl.md) の開発用 ACL ヘルパーを使用してください。

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
│   ├── CLI/                    # MCP server entry point and 6 tool implementations
│   │   └── Tools/              # GetBacklinks, GetHeadings, GetTags, ListNotes, ReadNote, SearchNotes
│   │                           # MCP サーバーエントリポイントと 6 ツール実装
│   ├── Diagnostics/            # Performance logging (PerfLogger)
│   │                           # パフォーマンスログ
│   ├── Models/                 # FileNode, EditorTab, DocumentTemplate, ColorTheme, Frontmatter, Backlink
│   ├── Views/
│   │   ├── MainWindowView.swift   # 3-pane layout (sidebar / editor / preview)
│   │   ├── E1/                    # E1 shell: Session rail, terminal pane, viewer tabs (Ghostty integration)
│   │   │                          # E1 シェル: セッションレール・ターミナルペイン・ビューアタブ
│   │   ├── Sidebar/               # FileTreeView, SearchView, OutlineView, BacklinksView, TagsView, TodoView
│   │   ├── Editor/                # NSTextView wrapper, TabBarView, FindReplaceBar, TemplatePickerView,
│   │   │                          #   FrontmatterEditor, QuickInsertView, WYSIWYGEditorView
│   │   ├── Diff/                  # DiffView, rendered Markdown diff (WKWebView-based)
│   │   ├── Help/                  # HelpWindowView, HelpContentView (in-app help)
│   │   ├── Preview/               # WKWebView-based Markdown + Mermaid + D2 renderer, CSVPreviewView
│   │   ├── QuickOpen/             # QuickOpenView (⌘P fuzzy file picker)
│   │   └── Settings/              # SettingsView
│   ├── ViewModels/             # @Observable state — FileTree, Preview, Search, Outline, DiffViewModel,
│   │                           #   FrontmatterViewModel, BacklinksViewModel, TagsViewModel,
│   │                           #   QuickOpenViewModel, CSVPreviewViewModel, D2PreviewViewModel
│   ├── Services/               # FileService, MarkdownService, GitService, BacklinksScanner,
│   │   │                       #   BacklinkContextChecker, WikiIndexService, TreeSitterHighlightService,
│   │   │                       #   MarkdownFormatterService, WorktreeService
│   │   └── Preview/            # ChromiumPreviewController, WorkspacePreviewHTTPServer
│   └── Resources/              # mermaid.min.js, easymde, AppIcon.icns, templates/
├── scripts/
│   ├── post-build.sh           # Bundles binary + resources → .app
│   └── keychain/               # Local development Keychain ACL helpers
├── Info.plist                  # App metadata + document type registration
└── Package.swift
```

**Stack:** SwiftUI + AppKit · MVVM (`@Observable`) · `swift-markdown` (Apple) · WKWebView · Mermaid.js · D2 · Tree-sitter · Ghostty (libghostty-spm)

---

## Keyboard Shortcuts / キーボードショートカット

### File / ファイル

| Shortcut | Action / アクション |
|----------|---------------------|
| ⌘O | Open folder / フォルダを開く |
| ⌘N | New file / 新規ファイル |
| ⌘⇧N | New file from template / テンプレートから新規ファイル |
| ⌘T | New tab / 新しいタブ |
| ⌘W | Close tab / タブを閉じる |
| ⌘S | Save / 保存 |
| ⌘⇧P | Export to PDF / PDF に書き出し |

### Edit / 編集

| Shortcut | Action / アクション |
|----------|---------------------|
| ⌘F | Find & Replace / 検索・置換 |
| ⌘P | Quick Open / クイックオープン |
| ⌘⌥K | Quick insert / クイックインサート |

### Format / フォーマット

| Shortcut | Action / アクション |
|----------|---------------------|
| ⌘B | Bold / 太字 |
| ⌘I | Italic / イタリック |
| ⌘K | Insert link / リンク挿入 |
| ⌘⇧F | Format document / ドキュメント整形 |

### View / 表示

| Shortcut | Action / アクション |
|----------|---------------------|
| ⌘⌥S | Toggle sidebar / サイドバー表示切替 |
| ⌘⇧R | Reading mode / 読書モード |
| ⌘= | Increase code font size / コードフォントを大きく |
| ⌘- | Decrease code font size / コードフォントを小さく |
| ⌘0 | Reset code font size / コードフォントを既定値に戻す |
| ⌘, | Settings / 設定 |
| ⌘? | Help / ヘルプ |

### E1 shell / E1 シェル

| Shortcut | Action / アクション |
|----------|---------------------|
| ⌘1 | Focus: terminal / フォーカス: ターミナル |
| ⌘2 | Focus: viewer / フォーカス: ビューア |
| ⌘3 | Focus: file tree / フォーカス: ファイルツリー |
| ⌘\ | Toggle Markdown split / Markdown スプリット切替 |

---

## Security / セキュリティ

kobaamd hardens the distributed binary against tampering and silent failure of the auto-update path.
配布バイナリの改竄・自動更新経路のサイレント失敗に対して、kobaamd は以下の防御を有効化しています。

- **Hardened Runtime** — Distributed `.app` is codesigned with `--options runtime` (ad-hoc signature). This blocks unsigned dylib injection, disables `DYLD_INSERT_LIBRARIES`, and is required for future Notarization. / 配布 `.app` は `--options runtime` 付きで codesign 済み（ad-hoc 署名）。未署名 dylib のインジェクションを防ぎ、将来の Notarization の前提条件を満たします。
- **Sparkle EdDSA signature verification** — Auto-updates are verified with an Ed25519 public key (`SUPublicEDKey` in `Info.plist`). The private key lives only in the release maintainer's macOS Keychain; the public key is injected at build time from `KOBAAMD_SU_PUBLIC_ED_KEY` and never committed to source. Release builds refuse to ship without it. / 自動更新は Ed25519 公開鍵で検証されます。秘密鍵はリリース担当の macOS Keychain にのみ存在し、公開鍵もソース管理に入れず `KOBAAMD_SU_PUBLIC_ED_KEY` 環境変数からビルド時に注入されます。release ビルドは未設定だと `exit 1` で停止します。
- **Multi-layer defense in build scripts** — Public key format validation (Base64 regex), quoted shell expansion, and write-back verification protect against silent failure of signature injection. / 公開鍵の形式バリデーション（Base64 正規表現）、シェル変数のクォート、書き込み後の読み戻し検証で、署名注入のサイレント失敗を防ぎます。
- **Local repo guards** — `pre-commit` hook scans for secret patterns (`sk-`, `ghp_`, `AKIA`, etc.) and blocks `.env` / `.pem` / `.key` / `credentials.json` from being committed. / `pre-commit` フックがシークレットパターンや禁止ファイル（`.env` / `.pem` / `.key` / `credentials.json` 等）のコミットを遮断します。

### Verifying a release / 配布物の検証

Before launching a binary downloaded from GitHub Releases, you can verify the signature and Hardened Runtime flag:
GitHub Releases から取得したバイナリは、起動前に以下で署名と Hardened Runtime フラグを確認できます。

```bash
# Confirm the runtime flag is set (look for "flags=...,runtime,...")
codesign --display --verbose=4 /Applications/kobaamd.app

# Verify the signature is intact
codesign --verify --deep --strict --verbose=2 /Applications/kobaamd.app
```

Expected: the `flags` line includes `runtime` (and `adhoc` for current ad-hoc signed builds), and `--verify` exits with status 0.
期待値: `flags` 行に `runtime` を含む（現状の ad-hoc 署名ビルドでは `adhoc` も含む）こと、`--verify` が exit 0 で終了すること。

### Known limits & roadmap / 既知の制限と今後

- App Sandbox は現在無効（フォルダワークスペースの自由なファイルアクセスを優先）。導入は将来検討。
- 一部のプレビュー（D2 ダイアグラム / 差分ビュー）は外部バイナリ呼び出し（`Process()`）に依存しており、WASM / Pure Swift 化を検討中。
- WKWebView でのプレビューに対する追加 XSS ハードニングを検討中。

実装の根拠と多層防御の詳細は `docs/wiki/articles/practices/security-hardening.md` と `docs/wiki/articles/practices/sparkle-release.md` を参照してください。
For implementation rationale and the multi-layer defense design, see `docs/wiki/articles/practices/security-hardening.md` and `docs/wiki/articles/practices/sparkle-release.md`.

---

## Roadmap / ロードマップ

- [x] **Rendered Markdown diff viewer** — See diffs as formatted Markdown, not raw syntax / レンダリング済み Markdown の差分ビューア
- [x] **TreeSitter syntax highlighting** — Full language support in code blocks / コードブロックの完全な言語サポート
- [x] **PDF export** — Export to PDF / PDF エクスポート
- [x] **E1 shell** — Ghostty terminal integration / Ghostty ターミナル統合
- [x] **MCP server** — Expose vault to AI clients via Model Context Protocol / MCP 経由で Vault を AI クライアントに公開

---

## Contributing / コントリビュート

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
貢献を歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

Vulnerability reports: see [SECURITY.md](SECURITY.md).
脆弱性報告: [SECURITY.md](SECURITY.md) をご覧ください。

---

## Third-party software / オープンソース利用

kobaamd is MIT-licensed, but it bundles and links other open-source components.
The E1 terminal embeds Ghostty's `libghostty` library (MIT) through the
`GhosttyTerminal` Swift package. Other dependencies include swift-markdown,
Tree-sitter, Mermaid.js, and EasyMDE.

- Full attribution and license texts: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- In-app: **Help → オープンソース** (⌘?)

kobaamd is not affiliated with or endorsed by the Ghostty project.

kobaamd 本体は MIT ですが、Ghostty ほか複数の OSS を組み込んでいます。
E1 ターミナルは `libghostty-spm` 経由で Ghostty（MIT）を利用しています。
帰属表示・全文は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) および
アプリ内ヘルプの「オープンソース」を参照してください。

---

## License / ライセンス

kobaamd source code: MIT — see [LICENSE](LICENSE).
Third-party components: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
