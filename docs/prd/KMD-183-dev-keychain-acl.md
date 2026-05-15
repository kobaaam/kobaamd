---
linear: KMD-183
status: in-progress
created_at: 2026-05-15
author: Codex
---

# 開発時 Keychain ACL partition-list 安定化

## 1. 背景・目的

kobaamd は AI API キーを macOS Keychain の generic password item として保存する。ローカル開発では ad-hoc 署名した `.app` を繰り返し再ビルドするため、macOS が再ビルド後のアプリを別署名として扱い、Keychain アクセス確認が繰り返される場合がある。

KMD-22 で `post-build.sh` の再署名は整備済みだが、開発者のローカル Keychain ACL を安定化する明示的な手順がない。Keychain ACL 更新は副作用が大きいため、ビルドスクリプトから自動実行せず、開発者が必要時に実行する opt-in helper として提供する。

## 2. ターゲットユーザーとユースケース

- `swift build && ./scripts/post-build.sh` を頻繁に実行する開発者
- API キーを保存済みの状態で、再起動のたびに Keychain access prompt が出るローカル環境

## 3. 機能要件

- `com.kobaamd.apikeys` service の既存 generic password items に対して partition-list を設定できる helper を追加する
- 対象 account は `openai`, `anthropic`, `confluenceURL`, `confluenceEmail`, `confluenceToken` を既定にする
- 実行既定は dry-run とし、`--apply` なしでは Keychain を変更しない
- ad-hoc / unsigned development build 向けの `unsigned:` partition は明示フラグ `--allow-unsigned-dev-app` のみで追加する
- API キー値、Keychain password、その他 secret を標準出力・ログ・ファイルに出さない

## 4. 非機能要件

- macOS 標準の `security` CLI のみを使う
- Keychain password を引数や環境変数として受け取らない
- 既存の `post-build.sh` の処理順序と codesign / Sparkle 公開鍵注入フローには触れない

## 5. UI/UX

CLI helper のみ。dry-run で対象 service / account / partition-list と missing item を確認できる。

## 6. 受け入れ条件

- [ ] `scripts/keychain/configure-dev-acl.sh` は `bash -n` を通る
- [ ] `scripts/keychain/configure-dev-acl.sh --dry-run --account openai` は Keychain を変更せず対象 item 有無を表示する
- [ ] `--allow-unsigned-dev-app` を付けた場合だけ `unsigned:` が partition-list に含まれる
- [ ] README から開発者向け手順に到達できる
- [ ] 手動確認: `--apply` 実行後、保存済み API キーを持つ ad-hoc build の再起動で Keychain prompt が繰り返されない

## 7. テスト戦略

- `bash -n scripts/keychain/configure-dev-acl.sh`
- dry-run 実行で Keychain item の存在確認と partition-list 組み立てを確認
- `swift build` / `swift test` で既存アプリコードに影響しないことを確認
- `--apply` はローカル Keychain を変更するため、この PR では自動実行しない

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `scripts/keychain/configure-dev-acl.sh` | 追加 | 開発者が明示実行する Keychain ACL helper |
| `docs/dev-keychain-acl.md` | 追加 | 手順・リスク・手動確認 |
| `README.md` | 変更 | Build セクションから手順へリンク |

**共有コンテナへの注意**:
- `scripts/post-build.sh` には追加しない。Keychain ACL mutation は build artifact 生成ではなくローカル環境設定。
- `Sources/Services/APIKeyStore.swift` の save/load/clear API には触れない。

### その他リスク

- `unsigned:` はローカル開発用途に限定する。共有・CI・本番配布用 Keychain では使わない。
- `security set-generic-password-partition-list` は Keychain ACL を変更するため、`--apply` は手動確認を前提にする。

## 9. 計測・成果指標

- ローカル開発時の Keychain access prompt 繰り返し発生数: 0

## 10. 参考資料

- Apple Developer Documentation: Access Control Lists
- `man security`: `set-generic-password-partition-list`
