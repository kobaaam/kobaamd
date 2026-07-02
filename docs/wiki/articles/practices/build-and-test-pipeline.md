---
title: ビルド・テストパイプライン手順と既知の罠
category: practices
tags: [build, test, swift, libghostty, ci, pipeline, fork]
sources:
  - scripts/prepare-build.sh
  - scripts/run-unit-tests.sh
  - Package.swift
created: 2026-07-02
updated: 2026-07-03
---

# ビルド・テストパイプライン手順と既知の罠

## Summary

**2026-07-02 (KMD-240) に fork 方式へ移行済み。** `swift build` 単独で成功する。`scripts/prepare-build.sh` は `swift package resolve` の薄いラッパーとして残っているが、呼び出しは任意。`ThirdParty/libghostty-spm-patches/` と `scripts/patch-libghostty-spm.sh` は削除済み。

## 正規ビルド手順
<!-- llm-context: KMD-240 以降、kobaamd は libghostty-spm の kobaaam fork (revision ピン) を使用する。パッチスクリプトは不要で swift build 単独で通る。 -->

```bash
swift build
```

以上だけで成功する。SPM が Package.swift の `revision` ピンをもとに `kobaaam/libghostty-spm` の `kobaamd-patches` ブランチのコミットを自動取得する。

`scripts/prepare-build.sh` は互換のため残っているが、内部で `swift package resolve` を呼ぶだけ（パッチ適用フェーズなし）。実行は任意。

## libghostty-spm fork 管理

| 項目 | 値 |
|------|-----|
| Fork URL | `https://github.com/kobaaam/libghostty-spm` |
| ブランチ | `kobaamd-patches` |
| ベースコミット | `c069f05e0a4ef50143e943e954ed75e52e947009`（upstream tag `1.2.4`） |
| 現在ピン SHA | `bde63c9360931f00a69e12524435f0a16a3f0157` |

Fork に含まれる kobaamd 追加 API（`E1AgentStatusMonitor` が必要とする）:

| ファイル | 配置先 |
|---------|--------|
| `TerminalSurface+ViewportRead.swift` | `Sources/GhosttyTerminal/Surface/` |
| `TerminalSurface+ScreenRead.swift` | 同上 |
| `AppTerminalView+ViewportRead.swift` | `Sources/GhosttyTerminal/Platform/AppKit/` |
| `AppTerminalView+ScreenRead.swift` | 同上 |

これらは `readViewportText` / `readScreenText` を提供する extension で、upstream PR 提出候補として `kobaamd-patches` コミットメッセージに記録してある。

## 歴史的経緯（移行前の旧方式 — 参照用）

2026-07-02 (KMD-240) 以前は `.build/checkouts/libghostty-spm/` に対して `scripts/patch-libghostty-spm.sh` でファイルを直接コピーするチェックアウトパッチ方式を採用していた。

- `scripts/prepare-build.sh` が `swift package resolve` → `patch-libghostty-spm.sh` の 2 ステップを実行
- パッチ未適用状態で `swift build` を実行すると `E1AgentStatusMonitor` のコンパイルで「`readViewportText` が見つからない」エラー
- この罠に起因して誤診断 hotfix PR #165 が作成・即クローズされた

**現在はこの問題は解消済み。`swift build` 単独で動作する。**

## テスト実行

### CI（デフォルト: 全件）

```bash
./scripts/run-unit-tests.sh
```

このスクリプトは `scripts/prepare-build.sh` → `swift build` → `swift test --enable-swift-testing --no-parallel` を一括実行する。**CI はフィルタなしで全テストを実行する**（KMD-245、2026-07-03）。

`main` への push 時は、全件テスト成功後に `RUN_BENCHMARKS=1` + `--filter HighlightBenchmarks` のベンチマーク job も別途走る。

### ローカル高速確認（安定サブセット）

```bash
./scripts/run-unit-tests.sh --stable-only
```

開発中の素早い確認用。以下の正規表現でフィルタされた安定サブセット（約 88 件）のみ実行する:

```
E1Terminal|E1AgentStatus|ColorTheme|EnclosedSymbol|CSVParser|BacklinksScanner|AppState
```

特定スイートだけを実行したい場合は `--filter` オプションで上書き可能:

```bash
./scripts/run-unit-tests.sh --filter CSVParser
```

### 全件実行（直接）

```bash
swift test --enable-swift-testing --no-parallel
```

**2026-07-03 時点のベースライン**: 474 tests / 全件 green。

### 結果行の確認を必須とする運用

`docs/ai-handoff.md` には「`swift test` が結果行なしで exit 0 する no-op 罠」が記録されている。2026-07-02 の実測ではこの挙動は再現しないが、**テスト実行後は結果行（`Test Suite 'All tests' passed...` 等）の出力を必ず目視確認すること**（結果行なしの exit 0 は no-op として疑う）。

## テストディレクトリ構造
<!-- llm-context: kobaamd のテストは PR #169 で層別ディレクトリに再編済み（2026-07-02 マージ）。TestSupport/Unit/Integration/ViewModel 等に分割。 -->

PR #169 で `Tests/kobaamdTests/` を `TestSupport` / `Unit` / `Integration` / `ViewModel` / `AppKitUI` / `Benchmarks` の層別ディレクトリに再編済み（2026-07-02 マージ）。

共通ユーティリティとして `TempWorkspace`（`final class` + `deinit` でテスト後のワークスペース自動クリーンアップ）と `eventually()`（非同期アサーション待機ヘルパー）が複数テストで使われている。詳細は `Tests/kobaamdTests/README.md` を参照。

## Related

- [[security-hardening]] — セキュリティ監査でも `scripts/` の堅牢化が対象
- [[dependency-inversion-guard]] — 依存スクリプト呼び出しの missing 時の guard パターン

## Sources

- `Package.swift`
- `scripts/prepare-build.sh`
- `scripts/run-unit-tests.sh`
