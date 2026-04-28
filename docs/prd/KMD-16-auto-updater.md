---
linear: KMD-16
status: in-progress
created_at: 2026-04-27
author: kobaamd_create_prd subagent
---

# 自動アップデート機能

## 1. 背景・目的

kobaamd は App Store を経由せず GitHub から直接配布される OSS エディタであり、現状はユーザーが手動で GitHub Release を確認し、ソースをクローン・ビルドするか DMG をダウンロードする必要がある。この手間がアップデートの適用率を下げ、バグ修正や新機能が届きにくくなる問題がある。

macOS の Sparkle フレームワーク（`sparkle-project/Sparkle`）を用いると、GitHub Releases の `appcast.xml` を定期ポーリングして新バージョンを検出し、DMG/ZIP の署名検証・ダウンロード・インストール・再起動を自動化できる。これは App Store に依存せず、無料で利用できる業界標準の仕組みである（VSCodium、Zed、Cursor 等が採用）。

## 2. ターゲットユーザーとユースケース

**ペルソナ A — 非エンジニアユーザー**: `swift build` コマンドを知らずに DMG からインストールしている。新バージョンが出たことを知る手段がなく、半年前のバグのある版を使い続けている。自動アップデートがあれば通知に従うだけで最新版を使える。

**ペルソナ B — 開発者ユーザー**: GitHub Release は認識しているが、kobaamd を日常使いしている間にアップデートを忘れがち。起動時の通知で「新バージョンがあります。今すぐ更新」を出してほしい。

## 3. 機能要件

### 必須要件

* アプリ起動時（または設定間隔ごと）に GitHub Releases の `appcast.xml` を HTTP(S) でポーリングし、現在の `AppVersion` より新しいバージョンが存在する場合はアップデートダイアログを表示すること
* Sparkle フレームワーク（Swift Package Manager 経由、`Package.swift` に依存追加）を採用すること
* GitHub Actions ワークフローで Release 時に `appcast.xml` を自動生成・更新する仕組みを整備すること（`scripts/` 配下にスクリプト追加）
* Sparkle の EdDSA 署名による DMG の整合性検証を必須とすること（改ざん防止）
* `SettingsView.swift` にアップデート確認間隔（起動時のみ / 毎日 / 毎週）を設定する UI を追加すること

### オプション要件

* バックグラウンドで自動ダウンロード・インストール後に再起動を促す「サイレントアップデート」モード
* アップデートを「今はしない」でスキップした場合に次回起動時に再通知しない「スキップ」機能

## 4. 非機能要件

* **パフォーマンス**: アップデートチェックはバックグラウンドスレッドで行い、UI をブロックしないこと。ネットワーク未接続時はサイレントに失敗し、次回起動時に再試行すること。
* **アクセシビリティ**: アップデートダイアログは Sparkle 標準 UI を使用し、VoiceOver 対応は Sparkle に委ねる。
* **macOS 整合性**: Sparkle は macOS 10.13 以降をサポート。kobaamd の要件 macOS 14 と一致。

## 5. UI/UX

起動時のアップデート通知ダイアログ（Sparkle 標準 UI）:

```
+-----------------------------------------------+
| kobaamd 1.x.0 が利用可能です                  |
|                                               |
| 現在: 1.0.0   新バージョン: 1.x.0             |
|                                               |
| リリースノート:                               |
| - バグ修正: スクロール同期                    |
| - 新機能: DnD ファイルオープン                |
|                                               |
| [今すぐインストール]  [後で]  [スキップ]      |
+-----------------------------------------------+
```

設定画面（`SettingsView.swift` への追加セクション）:

```
+-----------------------------------+
| アップデート                      |
|                                   |
| 自動確認: [起動時のみ v]          |
| [今すぐ確認]                      |
+-----------------------------------+
```

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `swift build` が成功し、Sparkle フレームワーク追加後もビルドエラーが 0 件であること
- [ ] アプリ起動時（または「今すぐ確認」ボタン押下時）に `appcast.xml` への HTTP(S) リクエストが発生し、アップデート確認が動作すること
- [ ] `AppVersion.swift` の現在バージョンより高いバージョンを `appcast.xml` に記述したとき、Sparkle のアップデートダイアログが表示されること
- [ ] `SettingsView` に「アップデート確認間隔」の設定 UI が追加されていること
- [ ] `Info.plist` に `SUPublicEDKey` と `SUFeedURL` が設定されていること

## 7. テスト戦略

* **単体テスト対象ファイル**:
  * `Sources/App/AppVersion.swift` — バージョン比較ロジックを追加する場合、バージョン文字列の大小比較テストを追加
* **手動確認項目**:
  1. `Package.swift` に Sparkle 依存追加後の `swift build` 成功確認
  2. ローカル HTTP サーバーで `appcast.xml` をホストし、起動時にダイアログが出ることを確認
  3. `SettingsView.swift` の設定 UI 動作確認

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Package.swift` | 変更 | Sparkle SPM 依存追加 |
| `Sources/App/kobaamdApp.swift` | 変更 | `SPUUpdater` の初期化・起動処理追加 |
| `Sources/Views/Settings/SettingsView.swift` | 変更 | アップデート確認設定 UI 追加 |
| `Sources/App/AppVersion.swift` | 変更の可能性あり | バージョン文字列の形式を Sparkle が期待する semver に揃える必要がある場合 |
| `Info.plist` | 変更 | `SUPublicEDKey`、`SUFeedURL` の追加 |
| `scripts/` | 追加 | `appcast.xml` 自動生成スクリプト、GitHub Actions ワークフロー |
| `Sources/Views/Updates/CheckForUpdatesView.swift` | 追加 | Sparkle updater メニュー項目 View（新規） |
| `Package.resolved` | 変更 | Sparkle 2.9.1 ピン追加（自動生成） |
| `scripts/generate-appcast.sh` | 追加 | appcast.xml 生成スクリプト |
| `Sources/Models/UpdateCheckInterval.swift` | 追加 | `UpdateCheckInterval` enum（atLaunch / daily / weekly）を独立ファイルに定義。`AppState.swift` および `SettingsView.swift` から参照 |
| `Sources/Services/AppState.swift` | 変更 | `updateCheckInterval` プロパティを `UserDefaults` バックエンドで追加。既存プロパティへの変更はなし |

**共有コンテナへの注意**:

* `kobaamdApp.swift` はアプリのエントリポイントで他の機能（AppDelegate、タブ復元等）も共存。Sparkle の `SPUUpdater` 初期化を追加する際に既存の `@main` ライフサイクルを壊さないよう注意。
* `SettingsView.swift` には既存の「AI プロバイダー」「Formatting」「クイックインサート テンプレート」セクションがある。これらは一切変更しないこと。

**変更してはいけない箇所**:
- `SettingsView.swift` の既存セクション（AI プロバイダー / Formatting / クイックインサート テンプレート / 保存ボタン）の動作・レイアウト
- `kobaamdApp.swift` の既存の `WindowGroup`、`Settings`、`AppDelegate`、`Notification.Name` 定義
- `AppCommand.swift` — 新コマンドは追加しない（アップデート確認は Sparkle が直接行う）
- `AppState.swift` — `autoFormatOnSave` など既存プロパティは変更しない。`updateCheckInterval` プロパティの追加は許容する（影響範囲マップに明記）
- `AppVersion.swift` のバージョン文字列フォーマット（`0.6.0` は既に semver 準拠なので変更不要）

**実装後の記録（事後）**:
- `Sources/Models/UpdateCheckInterval.swift` を新規追加（影響範囲マップに追記済み）
- `Sources/Services/AppState.swift` に `updateCheckInterval` プロパティを追加（影響範囲マップに追記済み）
- UpdateCheckerService.swift は不要と判断（Sparkle は SPUStandardUpdaterController 1クラスで完結し、ラッパー不要）
- SettingsView の height を 320→400 に変更（アップデートセクション追加分）

### その他リスク

* **Hardened Runtime**: Sparkle の一部機能（XPC サービス）は Hardened Runtime と相互作用する。kobaamd が現時点でコード署名なし配布であれば、Sparkle 統合でコード署名が必須になる可能性がある（現状を要確認）。
* **appcast.xml のホスト先**: GitHub Pages か GitHub Releases の asset として配置する方針を決める必要がある。
* **外部依存**: `sparkle-project/Sparkle` v2.x（SPM 対応済み）。MIT ライセンス。

## 9. 計測・成果指標

リリース後評価のため未定義。

## 10. 参考資料

* [Sparkle フレームワーク公式](https://sparkle-project.org/) — macOS OSS アプリの自動アップデート標準
* [Sparkle Swift Package Manager ガイド](https://sparkle-project.org/documentation/package-manager/)
* 類似 OSS 採用例: Zed Editor、VSCodium
