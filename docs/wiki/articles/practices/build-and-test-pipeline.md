---
title: ビルド・テストパイプライン手順と既知の罠
category: practices
tags: [build, test, swift, libghostty, ci, pipeline, patch]
sources:
  - scripts/prepare-build.sh
  - scripts/patch-libghostty-spm.sh
  - scripts/run-unit-tests.sh
created: 2026-07-02
updated: 2026-07-02
---

# ビルド・テストパイプライン手順と既知の罠

## Summary

kobaamd の正規ビルドは `bash scripts/prepare-build.sh && swift build` の 2 ステップが必須。`swift build` 単独では `E1AgentStatusMonitor` に関連するビルドエラーが発生する。テスト実行は CI 用の安定サブセット（`scripts/run-unit-tests.sh`）と全件実行の 2 モードがある。

## 正規ビルド手順
<!-- llm-context: kobaamd では libghostty-spm に対してパッチを当てないと swift build が失敗する。この手順を踏まずに swift build 単独で実行してはいけない。 -->

```bash
bash scripts/prepare-build.sh
swift build
```

`scripts/prepare-build.sh` は以下を順番に実行する:

1. `swift package resolve` — SPM 依存関係を解決して `.build/checkouts/` に展開
2. `bash scripts/patch-libghostty-spm.sh` — libghostty-spm のチェックアウトに kobaamd 固有の extension ファイル 4 件を注入

注入されるパッチファイル（`ThirdParty/libghostty-spm-patches/` に格納）:

| ファイル | 注入先 |
|---------|--------|
| `AppTerminalView+ViewportRead.swift` | `.build/checkouts/libghostty-spm/Sources/GhosttyTerminal/Platform/AppKit/` |
| `AppTerminalView+ScreenRead.swift` | 同上 |
| `TerminalSurface+ViewportRead.swift` | `.build/checkouts/libghostty-spm/Sources/GhosttyTerminal/Surface/` |
| `TerminalSurface+ScreenRead.swift` | 同上 |

これらのパッチは `readViewportText` / `readScreenText` を `AppTerminalView` と `TerminalSurface` に追加する extension で、`E1AgentStatusMonitor` が必要としている。

### 素の swift build が失敗する理由

`swift build` 単独（prepare-build.sh を経由しない）では、チェックアウト済みの libghostty-spm にパッチが当たっていないため `E1AgentStatusMonitor` のコンパイル時に「`readViewportText` が見つからない」エラーが発生する。

**教訓（2026-07-02）**: パッチ機構を知らずに `E1AgentStatusMonitor` のコードそのものを修正しようとする誤診断が発生し、hotfix PR #165 が作成された。しかし実際の原因はパッチ未適用であり、PR は即クローズされた。**ビルドエラーを見たら、まず `prepare-build.sh` を実行したかを確認すること**。

## テスト実行

### CI 用安定サブセット（推奨）

```bash
bash scripts/run-unit-tests.sh
```

このスクリプトは `prepare-build.sh`（resolve + patch）→ `swift build` → `swift test` を一括実行する。テスト対象は以下の正規表現でフィルタされた安定サブセット:

```
E1Terminal|E1AgentStatus|ColorTheme|EnclosedSymbol|CSVParser|BacklinksScanner|AppState
```

特定スイートだけを実行したい場合は `--filter` オプションで上書き可能:

```bash
bash scripts/run-unit-tests.sh --filter CSVParser
```

### 全件実行

```bash
bash scripts/prepare-build.sh
swift test --enable-swift-testing --no-parallel
```

**2026-07-02 時点のベースライン**: 344 tests / 既存失敗 4 件（`WikiIndexService` ×2、`TodoViewModel` ×2）。この 4 件は既知の失敗であり、回帰ではない。

### 結果行の確認を必須とする運用

`docs/ai-handoff.md` には「`swift test` が結果行なしで exit 0 する no-op 罠」が記録されている。2026-07-02 の実測ではこの挙動は再現せず、結果行（`Test Suite 'All tests' passed...` 等）が出力された。ただし環境依存の可能性があるため、**テスト実行後は結果行の出力を必ず目視確認すること**（結果行なしの exit 0 は no-op として疑う）。

## テストディレクトリ構造
<!-- llm-context: kobaamd のテストは Tests/kobaamdTests/ 直下にフラットに配置されている（2026-07-02 時点。サブディレクトリ型への再構築は別 PR で検討中）。 -->

2026-07-02 時点では `Tests/kobaamdTests/` 直下にすべてのテストファイルがフラットに配置されている。テストスイートの再構築（`TestSupport` / `Unit` / `Integration` / `ViewModel` / `AppKitUI` / `Benchmarks` のサブディレクトリ分割）は設計検討中だが、該当 PR はまだ作成されていない。

共通ユーティリティとして `TempWorkspace`（`final class` + `deinit` でテスト後のワークスペース自動クリーンアップ）と `eventually()`（非同期アサーション待機ヘルパー）が複数テストで使われている。

## Related

- [[security-hardening]] — セキュリティ監査でも `scripts/` の堅牢化が対象になっている
- [[dependency-inversion-guard]] — `prepare-build.sh` のような依存スクリプト呼び出しの missing 時の guard パターン

## Sources

- `scripts/prepare-build.sh`
- `scripts/patch-libghostty-spm.sh`
- `scripts/run-unit-tests.sh`
- `ThirdParty/libghostty-spm-patches/`
