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
