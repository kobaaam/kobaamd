---
linear: KMD-27
status: in-progress
created_at: 2026-04-30
author: kobaamd_implement_code subagent
---

# Sparkle EdDSA 公開鍵（SUPublicEDKey）の設定

## 1. 背景・目的

kobaamd はビジョン「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」を掲げ、OSS として DMG 配布を行っている。[KMD-16](https://linear.app/kobaan/issue/KMD-16) で Sparkle フレームワークによる自動アップデート機構を導入したが、`Info.plist` の `SUPublicEDKey` が空文字列のままマージされた（KMD-6 の振り返り `docs/learnings/2026-04-28-KMD-6.md` で指摘済み）。

鍵なしの状態では Sparkle が署名検証をスキップするため、中間者攻撃（MITM）によりアップデート配信経路で改ざんされたバイナリを受け入れるリスクがある。GitHub Releases の HTTPS 保護があるとはいえ、Sparkle の EdDSA 署名検証は多層防御の要であり、OSS プロジェクトとしてのセキュリティ信頼性を確保するために早急な対応が必要。

本タスクは KMD-26（Hardened Runtime 有効化）の前提条件でもあり、セキュリティ基盤強化ロードマップの一部を担う。

> **本タスクの位置づけ**: 実際の鍵生成（Keychain への登録）は人間オペレーション扱いとする。本実装では「鍵が未設定のときに分かりやすく失敗・警告する仕組み」「公開鍵を Info.plist に外部から注入できる仕組み」「リリース手順の文書化」「`.gitignore` の整備」を行う。

## 2. ターゲットユーザーとユースケース

### ペルソナ A: kobaamd エンドユーザー（DMG 配布利用者）

- DMG でインストールし、Sparkle の自動アップデート通知を受け取る
- 期待: アップデートが署名検証された安全なバイナリであること

### ペルソナ B: プロジェクトメンテナー（リリース担当）

- 新バージョンの DMG をビルドし、署名付き appcast.xml を生成して GitHub にプッシュする
- 期待: `generate_keys` で生成した秘密鍵を Keychain に保管し、`sign_update` で DMG を署名し、`generate-appcast.sh` で appcast.xml を生成する手順が一本化されていること

### ペルソナ C: OSS コントリビューター

- リポジトリをクローンしてビルドする
- 期待: 秘密鍵がリポジトリに含まれていないこと、公開鍵未設定でもビルド自体は成功すること（ただし警告は出る）

## 3. 機能要件

### 必須要件

- **EdDSA 鍵ペア生成手順の整備**: Sparkle の `generate_keys` ツールを使用して Ed25519 鍵ペアを生成する手順をドキュメント化する。秘密鍵は実行マシンの Keychain に保存される（リポジトリにはコミットしない）
- **公開鍵の Info.plist への注入**: `SUPublicEDKey` を環境変数 `KOBAAMD_SU_PUBLIC_ED_KEY` から `scripts/post-build.sh` 経由で注入する仕組みを追加する。ソース管理上の `Info.plist` は空文字列のままでよい（Codex 実装注: ただし「空のまま `.app` にコピーしない」ことが本タスクのゴール）
- **未設定時の警告**: 公開鍵が未設定のまま `post-build.sh` を実行した場合は警告ログを出し、リリースビルド（`release` 引数）の場合はエラー終了する。デバッグビルドでは警告のみ
- **`generate-appcast.sh` の補強**: 引数で渡された署名が空文字列でないことのバリデーションを追加し、空のときは即時 `exit 1`
- **リリース手順ドキュメント**: `docs/wiki/articles/practices/sparkle-release.md`（新規）に「鍵生成 → 公開鍵を環境変数に設定 → DMG ビルド → 署名 → appcast 生成 → アップロード」の流れを記載
- **`.gitignore` への秘密鍵パターン追加**: `eddsa_priv*`, `*.pem`, `*_priv_key*` 等を追加（防御的記述）

### オプション要件

- 将来の CI（GitHub Actions）で `SUPublicEDKey` のフォーマット（44文字 Base64）を検証するステップ
- Keychain アクセス確認ユーティリティ（手動）

## 4. 非機能要件

- **パフォーマンス**: アップデートチェック時の署名検証は Sparkle 内部で行われ、ユーザー体感に影響なし
- **アクセシビリティ**: UI 変更なし
- **macOS との整合性**: Keychain は macOS 標準のセキュアストレージ。Hardened Runtime（KMD-26）後も利用可能

## 5. UI/UX

UI 変更なし。署名検証失敗時は Sparkle 標準のエラーダイアログが表示される（カスタマイズ不要）。

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `Info.plist` に `SUPublicEDKey` キーは存在し、`scripts/post-build.sh` が `KOBAAMD_SU_PUBLIC_ED_KEY` を読んで `.app/Contents/Info.plist` に注入する
- [ ] 公開鍵未設定時、`post-build.sh debug` は警告ログを出すが終了は成功（デバッグ開発を妨げない）
- [ ] 公開鍵未設定時、`post-build.sh release` はエラーログを出し非ゼロで終了する
- [ ] `scripts/generate-appcast.sh` は署名引数が空文字列の場合、エラーで終了する
- [ ] `.gitignore` に秘密鍵パターン（`eddsa_priv*`, `*.pem`）が含まれている
- [ ] `docs/wiki/articles/practices/sparkle-release.md` が存在し、鍵生成・署名・appcast 生成の手順が記載されている
- [ ] `swift build` がエラーなしで完了する
- [ ] 既存のテストが通る（`swift test`）
- [ ] Info.plist のリポジトリ版を `git diff` で確認したとき、秘密鍵が含まれない

## 7. テスト戦略

- **シェルスクリプト**: `bash -n scripts/post-build.sh` および `bash -n scripts/generate-appcast.sh` で構文チェック
- **手動確認**:
  | 手順 | 期待結果 |
  | -- | -- |
  | `unset KOBAAMD_SU_PUBLIC_ED_KEY && ./scripts/post-build.sh debug` | 警告ログを出して終了コード 0 |
  | `unset KOBAAMD_SU_PUBLIC_ED_KEY && ./scripts/post-build.sh release` | エラーログを出して終了コード 非0 |
  | `KOBAAMD_SU_PUBLIC_ED_KEY=AAAA... ./scripts/post-build.sh debug` | `.app/Contents/Info.plist` の `SUPublicEDKey` に値が入っている |
  | `./scripts/generate-appcast.sh 0.7.0 https://... "" 12345` | エラー終了 |
- **swift build / swift test**: ビルド・既存テストが通ること

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
| -- | -- | -- |
| `Info.plist` | 変更（コメント更新のみ） | `SUPublicEDKey` の値は空のまま。注入は `post-build.sh` で行う旨のコメントを追加 |
| `scripts/post-build.sh` | 変更 | 環境変数 `KOBAAMD_SU_PUBLIC_ED_KEY` を読んで `.app/Contents/Info.plist` に PlistBuddy で注入する処理を追加。release ビルド時の検証 |
| `scripts/generate-appcast.sh` | 変更 | 署名引数の空文字バリデーションを強化（既存の `-z` チェックは "" を弾けるが、より明示的なエラーメッセージに） |
| `.gitignore` | 変更 | `eddsa_priv*`, `*.pem`, `*_priv_key*` パターン追加 |
| `docs/wiki/articles/practices/sparkle-release.md` | 追加 | 署名付きリリース手順ドキュメント（新規） |
| `docs/wiki/index.md` | 変更 | 新規記事のリンクを追加 |

**共有コンテナへの注意（変更してはいけない箇所）:**

- `Info.plist`: `CFBundleDisplayName` / `CFBundleIdentifier` / `CFBundleShortVersionString` / `CFBundleVersion` / `CFBundleDocumentTypes` / `UTImportedTypeDeclarations` / `LSMinimumSystemVersion` / `SUFeedURL` 等は **一切変更しない**。`SUPublicEDKey` 周辺のコメントと（必要なら）キーの位置のみ
- `scripts/post-build.sh`: 既存のバイナリコピー・アイコン注入・bundle copy・`Info.plist` 上書き・Sparkle.framework コピー・codesign 等の処理を **壊さない**。新規処理は `Info.plist` 上書きの **直後** に追加する
- `scripts/generate-appcast.sh`: 既存の出力 XML フォーマット（タグ構造・URL）は変えない。バリデーション強化のみ
- Swift コード（`Sources/**`）: 触らない。本タスクは設定・ビルドスクリプト・ドキュメントのみ

### その他リスク

- **公開鍵の管理**: 環境変数で渡す方式は CI/手元シェルから取り扱う必要がある。リリース手順書にこの依存を明記する
- **Keychain の機種依存**: `generate_keys` の秘密鍵は実行マシン依存。Keychain エクスポート手順をドキュメントに含める
- **既存ユーザーへの影響**: 公開鍵が設定された後のリリースから署名検証が有効になる。Sparkle v2 は初回遷移を安全に処理する
- **外部依存**: Sparkle v2.9.1（`Package.swift` に既定義）の `generate_keys` および `sign_update` CLI

## 9. 計測・成果指標

- 署名検証成功率: 署名付きリリース後 100%
- セキュリティ監査: `kobaamd_review_security` のチェック項目をパス

## 10. 参考資料

- [Sparkle EdDSA 署名ガイド](https://sparkle-project.org/documentation/eddsa-setup/)
- [Sparkle sign_update CLI](https://sparkle-project.org/documentation/publishing/)
- `docs/learnings/2026-04-28-KMD-6.md` — SUPublicEDKey 空文字問題の振り返り
- `docs/prd/KMD-16-auto-updater.md` — Sparkle 自動アップデート PRD
- `docs/adr/0008-sparkle-auto-update.md` — Sparkle 採用 ADR
