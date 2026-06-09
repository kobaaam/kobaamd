# Third-Party Notices

kobaamd incorporates open-source software. The following notices apply to
components shipped with or linked into the application.

## Summary

| Component | Use in kobaamd | License | Upstream |
|-----------|----------------|---------|----------|
| [Ghostty](https://ghostty.org) | E1 embedded terminal (via libghostty binary) | MIT | [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) |
| [libghostty-spm](https://github.com/Lakr233/libghostty-spm) | Swift Package / XCFramework wrapper (`GhosttyTerminal`) | MIT | [Lakr233/libghostty-spm](https://github.com/Lakr233/libghostty-spm) |
| [MSDisplayLink](https://github.com/Lakr233/MSDisplayLink) | Transitive dependency of libghostty-spm | MIT | [Lakr233/MSDisplayLink](https://github.com/Lakr233/MSDisplayLink) |
| [swift-markdown](https://github.com/apple/swift-markdown) | Markdown parsing / rendering | Apache-2.0 | Apple |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | Transitive dependency of swift-markdown | [cmark license](https://github.com/swiftlang/swift-cmark/blob/main/LICENSE) | swiftlang |
| [swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter) | Syntax highlighting | MIT | tree-sitter |
| [tree-sitter](https://github.com/tree-sitter/tree-sitter) | Transitive dependency | MIT | tree-sitter |
| [tree-sitter-markdown](https://github.com/tree-sitter-grammars/tree-sitter-markdown) | Markdown grammar | MIT | tree-sitter-grammars |
| [Mermaid.js](https://mermaid.js.org) | Bundled in preview WebView | MIT | mermaid-js |
| [EasyMDE](https://github.com/Ionaru/easy-markdown-editor) | Bundled editor helper | MIT | Ionaru |

Resolved package versions are recorded in [Package.resolved](Package.resolved).

---

## Ghostty

```
MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

kobaamd embeds a trimmed `libghostty` build distributed through libghostty-spm.
This product is not affiliated with or endorsed by the Ghostty project.

---

## libghostty-spm

```
MIT License

Copyright (c) 2026 @Lakr233

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## MSDisplayLink

```
MIT License

Copyright (c) 2024 Lakr Aream

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```