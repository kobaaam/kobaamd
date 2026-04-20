# Contributing to kobaamd

Thank you for your interest in contributing!

## Getting Started

```bash
git clone https://github.com/kobaaam/kobaamd.git
cd kobaamd
swift build
./scripts/post-build.sh
open .build/kobaamd.app
```

## Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Build and test: `swift build && ./scripts/post-build.sh && open .build/kobaamd.app`
5. Commit with a clear message
6. Open a Pull Request

## Code Style

- Swift standard conventions
- MVVM architecture — keep Views thin, logic in ViewModels/Services
- No third-party dependencies beyond `swift-markdown` (Apple official)
- Prefer `@Observable` over `ObservableObject`
- All disk I/O must run on background threads (`Task.detached`)

## What to Contribute

Good first issues:
- Bug fixes
- Syntax highlighting improvements
- Performance improvements
- Accessibility (VoiceOver support)
- Localization

Please open an issue before starting large features to discuss approach.

## Reporting Bugs

Include:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Relevant log output if available

## License

By contributing, you agree your code will be released under the [MIT License](LICENSE).
