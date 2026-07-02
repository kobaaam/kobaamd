---
title: ビルド・テストパイプライン手順と既知の罠
category: practices
tags: [build, test, swift, libghostty, ci, pipeline, fork]
sources:
  - scripts/prepare-build.sh
  - scripts/run-unit-tests.sh
  - Package.swift
created: 2026-07-02
updated: 2026-07-02
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

## fork 保守手順

### upstream 新バージョン追随

upstream（Lakr233/libghostty-spm）が新しいタグをリリースした場合:

```bash
# 1. kobaaam fork を最新の upstream に sync
cd /path/to/libghostty-fork
git fetch upstream          # upstream remote がなければ git remote add upstream https://github.com/Lakr233/libghostty-spm.git
git checkout kobaamd-patches
git rebase upstream/<new-tag>   # コンフリクトがあれば後述の手順で解消

# 2. rebase が成功したら force push（kobaamd-patches は kobaamd 専用ブランチ）
git push origin kobaamd-patches --force-with-lease

# 3. 新しい HEAD SHA を控える
git rev-parse HEAD
# → <new-sha>

# 4. kobaamd 側の Package.swift を更新
#    revision: "<new-sha>" に書き換えて swift package resolve を実行
cd /path/to/kobaamd
# Package.swift の revision を <new-sha> に変更
swift package resolve

# 5. クリーンビルドで確認
rm -rf .build && swift build
```

### rebase コンフリクトの対応

`kobaamd-patches` が追加するファイルは upstream には存在しないため、通常コンフリクトは発生しない。もし upstream が同名ファイルを追加した場合（= upstream に API がマージされた）は後述の「fork 廃止手順」に進む。それ以外のコンフリクトは diff を見て手動解消してコミットを続行する。

### fork 廃止手順（upstream に API がマージされた場合）

upstream に `readViewportText` / `readScreenText` がマージされた場合は fork を廃止して元の URL に戻す:

```bash
# Package.swift を元の upstream URL + from バージョン指定に戻す
# .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "<merged-version>")
swift package resolve
rm -rf .build && swift build   # クリーンビルドで確認
```

fork (`https://github.com/kobaaam/libghostty-spm`) は参照が外れた後も GitHub 上に残るが、kobaamd-patches ブランチは archive しておいてよい。

## 歴史的経緯（移行前の旧方式 — 参照用）

2026-07-02 (KMD-240) 以前は `.build/checkouts/libghostty-spm/` に対して `scripts/patch-libghostty-spm.sh` でファイルを直接コピーするチェックアウトパッチ方式を採用していた。

- `scripts/prepare-build.sh` が `swift package resolve` → `patch-libghostty-spm.sh` の 2 ステップを実行
- パッチ未適用状態で `swift build` を実行すると `E1AgentStatusMonitor` のコンパイルで「`readViewportText` が見つからない」エラー
- この罠に起因して誤診断 hotfix PR #165 が作成・即クローズされた

**現在はこの問題は解消済み。`swift build` 単独で動作する。**

## テスト実行

### CI 用安定サブセット（推奨）

```bash
./scripts/run-unit-tests.sh
```

このスクリプトは `swift package resolve` → `swift build` → `swift test` を一括実行する。テスト対象は以下の正規表現でフィルタされた安定サブセット:

```
E1Terminal|E1AgentStatus|ColorTheme|EnclosedSymbol|CSVParser|BacklinksScanner|AppState
```

特定スイートだけを実行したい場合は `--filter` オプションで上書き可能:

```bash
./scripts/run-unit-tests.sh --filter CSVParser
```

### 全件実行

```bash
swift test --enable-swift-testing --no-parallel
```

**2026-07-02 時点のベースライン**: 344 tests / 既存失敗 4 件（`WikiIndexService` ×2、`TodoViewModel` ×2）。この 4 件は既知の失敗であり、回帰ではない。

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
