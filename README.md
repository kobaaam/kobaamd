# kobaamd

**The Mac-native Markdown editor built for the AI era.**

kobaamd is a lightweight, fast Markdown editor for macOS — designed around how engineers actually work with AI-generated content today. No Electron. No subscriptions. No bloat.

---

## Why kobaamd?

AI tools like Claude and ChatGPT generate a lot of Markdown — READMEs, specs, docs, notes. Existing editors all miss the mark for engineers:

| Tool | Problem |
|------|---------|
| Typora | Electron-based, slow to launch |
| Bear | Proprietary DB, no Git integration |
| Obsidian | Feature overload, steep learning curve |
| iA Writer | Too minimal, no AI integration |
| VS Code | Not Markdown-native, too heavy |

kobaamd fills the gap: **Mac-native speed × clean UI × folder-based workflow × Mermaid diagrams**.

---

## Features

- **Instant preview** — Split view (editor + rendered Markdown side by side) or WYSIWYG mode
- **Folder workspace** — Open a folder and browse all files in a sidebar tree
- **Mermaid diagrams** — Flowcharts, sequence diagrams, Gantt charts rendered inline
- **Tabbed editing** — Multiple files open simultaneously (⌘T for new tab)
- **Syntax highlighting** — Markdown syntax highlighted in the editor
- **Full-text search** — Search across all files in your workspace
- **Git panel** — View branch and status at a glance
- **AI assist** — Send selected text to OpenAI / Anthropic / Gemini (API key required)
- **Autosave** — Changes saved automatically; manual save with ⌘S
- **macOS native** — SwiftUI + AppKit, macOS 14+, Apple Silicon optimized
- **Offline-first** — Mermaid.js and EasyMDE bundled, no CDN required

---

## Screenshots

> _Split view: editor on the left, live Markdown preview on the right_

```
┌─────────────────┬──────────────────────────────┐
│  EXPLORER       │ ## Hello kobaamd              │
│                 │                               │
│  README.md   ●  │ A lightweight Markdown editor │
│  CHANGELOG.md   │ for the AI era.               │
│  docs/          │                               │
│    spec.md      │ ┌─────────────────────────┐   │
│    notes.md     │ │  flowchart TD           │   │
│                 │ │    A --> B --> C         │   │
│                 │ └── [Mermaid diagram] ─────┘   │
└─────────────────┴──────────────────────────────┘
```

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (arm64) — Intel untested

---

## Build

kobaamd uses Swift Package Manager. No Xcode project required.

```bash
# Clone
git clone https://github.com/kobaaam/kobaamd.git
cd kobaamd

# Build
swift build

# Bundle into .app (copies binary + resources + app icon)
./scripts/post-build.sh

# Launch
open .build/kobaamd.app
```

### Release build

```bash
swift build -c release
./scripts/post-build.sh release
open .build/kobaamd.app
```

### Set as default Markdown editor

After launching once, open any `.md` file in Finder → **Get Info (⌘I)** → "Open With" → select **kobaamd** → **"Change All…"**

---

## Architecture

```
kobaamd/
├── Sources/
│   ├── App/                    # Entry point, AppViewModel, commands
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

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘O | Open folder |
| ⌘N | New file |
| ⌘T | New tab |
| ⌘W | Close tab |
| ⌘S | Save |
| ⌘F | Find & Replace |
| ⌘B | Toggle sidebar |
| ⌘G | Toggle Git panel |
| ⌘E | AI assist |
| ⌘, | Settings |

---

## Roadmap

- [ ] **Rendered Markdown diff viewer** — See diffs as formatted Markdown, not raw syntax
- [ ] **TreeSitter syntax highlighting** — Full language support in code blocks
- [ ] **Export** — PDF, HTML export
- [ ] **Outline panel** — Navigate headings
- [ ] **Custom themes** — Light/dark/custom color schemes
- [ ] **Apple Silicon notarization** — App Store / direct download

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT — see [LICENSE](LICENSE).
