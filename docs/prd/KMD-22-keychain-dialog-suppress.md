---
linear: KMD-22
status: todo
created_at: 2026-04-28
author: kobaamd_implement_code
---

# 起動時キーチェーンアクセスダイアログ抑止

## 1. 背景・目的

kobaamd は「Mac で最も快適に AI 生成 Markdown を扱えるエディタ」を目指している。v0.6 で追加した Confluence 同期機能（KMD-8）が APIKeyStore 経由で macOS Keychain に API トークンを保存しており、起動のたびにシステムダイアログ「kobaamd がキーチェーンの項目にアクセスしようとしています」が表示される問題が発生している。

根本原因: `scripts/post-build.sh` がビルド後にバイナリを差し替える際に `codesign` をかけ直していないため、Bundle Identifier がハッシュベース（`kobaamd-55554944...`）になる。キーチェーン ACL は元署名の Bundle ID に紐付いているため、差し替え後は毎回別アプリとみなされてダイアログが出る。

## 2. ターゲットユーザーとユースケース

- **開発者**: ビルド・起動するたびにダイアログが出て開発体験が損なわれる
- **エンドユーザー**: `.app` をそのまま使う場合も、バイナリ差し替え後に署名が外れていると同様の問題が起きる

## 3. 機能要件

- 必須要件:
  - `scripts/post-build.sh` でバイナリを差し替えた後、`codesign --force --deep -s -` で ad-hoc 再署名する
  - 再署名後にキーチェーンアクセスダイアログが出ないことを確認する
  - Info.plist のコピーも署名前に行う（Bundle ID が正しく設定された状態で署名する）

- オプション要件:
  - 将来的に Apple Developer ID 署名（`-s "Developer ID Application: ..."` ）への切り替えが容易な構造にする
  - entitlements ファイルを用意して `--entitlements` オプションで渡せるようにする

## 4. 非機能要件

- パフォーマンス: `codesign` コマンドは数秒以内に完了すること
- macOS との整合性: ad-hoc 署名（`-s -`）は配布不可だが開発用途では許容範囲

## 5. UI/UX

ユーザー操作なし。起動時にダイアログが出なくなる。

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `swift build && ./scripts/post-build.sh` 実行後、`codesign -dv .build/kobaamd.app` で `Signature=adhoc` かつ `Identifier=com.kobaamd.app` が表示される
- [ ] `open .build/kobaamd.app` で起動しても「キーチェーンアクセス」ダイアログが出ない（APIキーが登録済みの場合）
- [ ] 既存の APIKeyStore の load/save/clear API に変更なし
- [ ] `swift test` が全件パス

## 7. テスト戦略

- 単体テスト: APIKeyStore の既存テストが通ること
- 手動確認: `swift build && ./scripts/post-build.sh && open .build/kobaamd.app` でダイアログが出ないこと

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `scripts/post-build.sh` | 変更 | バイナリコピー後に `codesign` 追加 |
| `Sources/Resources/kobaamd.entitlements`（新規） | 追加 | `com.apple.security.keychain-access-groups` などを定義（オプション） |

**共有コンテナへの注意**:
- `post-build.sh` は `.app` バンドル全体を操作するスクリプト。アイコン・Info.plist・バイナリの各コピーは現行の順序を維持すること
- 変更してはいけない箇所:
  - `Sources/Services/APIKeyStore.swift` の API（load/save/clear）
  - `Info.plist` の既存エントリ（CFBundleIdentifier = `com.kobaamd.app` は変更しない）
  - `Package.swift` の依存ライブラリ

### その他リスク

- 既存コードへの影響: なし（スクリプトのみ）
- 互換性: ad-hoc 署名のため App Store / Notarization 不可（開発用途のみ）
- 外部依存: `codesign` コマンド（Xcode Command Line Tools に付属、常に利用可能）

## 9. 計測・成果指標

- 起動時キーチェーンダイアログ出現回数: 0

## 10. 参考資料

- [Apple: Signing a Mac Product For Distribution](https://developer.apple.com/documentation/xcode/signing-a-mac-product-for-distribution)
- [codesign man page](x-man-page://codesign)
