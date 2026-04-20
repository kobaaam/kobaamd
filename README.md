# kobaamd

Your Mac's most comfortable companion for AI-generated Markdown.

[![macOS](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Screenshot

<!-- TODO: Add screenshot -->
_Screenshot coming soon._

---

## Vision

> **The most comfortable Mac-native editor for AI-generated Markdown.**

kobaamd is built for engineers who work with AI tools daily — reviewing Claude outputs, refining ChatGPT drafts, managing technical docs and READMEs. Unlike Electron-based alternatives, kobaamd is pure SwiftUI + AppKit: instant startup, low memory, native feel.

---

## Features

| | Feature |
|---|---|
| ⚡️ | **Fast NSTextView editor** — syntax highlighting, line numbers, smart autocomplete |
| 👁️ | **Real-time preview** — split-pane or WYSIWYG (EasyMDE, bundled offline) |
| ↔️ | **Scroll sync** — editor and preview stay in lockstep |
| ✍️ | **Markdown autocomplete** — brackets, list continuation, code fence closing |
| 🖼️ | **Image paste** — auto-saves to `./assets/`, inserts `![]()` link |
| 📊 | **Mermaid.js diagrams** — rendered inline in preview |
| 📁 | **Folder tree** — create, rename, delete files without leaving the editor |
| 🔍 | **Full-text search** — across the entire open folder |
| 🌲 | **Git integration** — staged/unstaged diff, commit, history (⌘G) |
| 🧠 | **AI integration** — OpenAI, Anthropic, Gemini with Keychain key storage |
| 💾 | **Autosave** — 3-second debounce, dirty indicator in toolbar |
| 📖 | **Open Recent** — last 10 files, auto-restores on launch |

---

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode 15+

---

## Build

```bash
git clone https://github.com/kobaaam/kobaamd.git
cd kobaamd
swift build -c release
# → .build/release/kobaamd
```

Or open in Xcode and hit ▶︎.

---

## Contributing

Issues and PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines (coming soon).

---

## License

MIT — see [LICENSE](LICENSE).
