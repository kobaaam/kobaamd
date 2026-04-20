# Contributing to kobaamd

Contributions are welcome! Please read this document before opening a PR.

---

## Setup

**Requirements:** macOS 14+, Xcode (Swift 5.9+), Git

```bash
git clone https://github.com/kobaaam/kobaamd.git
cd kobaamd
swift build   # verify it builds
swift test    # verify tests pass
```

---

## Coding Guidelines

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Keep views small and composable
- Use `@Observable`, `@State`, `@Binding`, `@Environment` appropriately
- Comments for non-obvious logic only — code should be self-documenting
- No dead code, no unused variables

---

## Submitting a PR

1. Fork the repo and create a branch:
   - Features: `feature/your-feature`
   - Fixes: `fix/issue-description`

2. Make your changes and ensure tests pass:
   ```bash
   swift test
   ```

3. Push and open a PR against `main`

4. CI runs `swift build` + `swift test` automatically — ensure it passes

5. Be responsive to review comments

---

## Reporting Issues

Search existing issues first. When opening a new issue:

**Bug report:** Steps to reproduce, expected vs. actual behavior, macOS version
**Feature request:** Description, why it's useful, mockup if possible

---

## Commit Message Format

```
type: short description

[optional body: what and why, not how]
```

**Types:** `feat` `fix` `docs` `refactor` `perf` `test` `ci` `chore`

**Examples:**
```
feat: add syntax highlighting for Swift code blocks
fix: prevent crash when opening invalid markdown file
docs: update README with build instructions
```

---

Thank you for contributing!
