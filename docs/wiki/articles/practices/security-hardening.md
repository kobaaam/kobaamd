---
title: セキュリティ・ハードニング（多層防御）
category: practices
tags: [security, supply-chain, secrets, pre-commit, pipeline, silent-failure]
sources: [docs/adr/0009-security-hardening.md, docs/learnings/2026-05-01-KMD-26.md, docs/learnings/2026-05-01-KMD-27.md]
created: 2026-04-29
updated: 2026-05-03
---

# セキュリティ・ハードニング（多層防御）

## Summary

AI 自律パイプラインに固有のリスク（シークレット漏洩、サプライチェーン攻撃、権限エスカレーション）を 3 層で防御。Layer 1（ローカル hooks）と Layer 2（パイプライン review_security）は即時導入済み。

## Content

### Layer 1: ローカル防御

**pre-commit hook** (`scripts/hooks/pre-commit`):
- Swift ビルド確認（既存）
- シークレットパターン検出（`sk-`, `ghp_`, `AKIA`, `xoxb-` 等）
- 禁止ファイル検出（`.env`, `.pem`, `.key`, `credentials.json` 等）

**`.gitignore`**: シークレット拡張子と `.mcp.json`（OAuth トークン含む）を除外。

**hooks のバージョン管理**: `scripts/hooks/` に配置、`install.sh` で `.git/hooks/` にシンボリックリンク。新しいクローンでも即セットアップ可能。

### Layer 2: パイプライン防御

**`kobaamd_review_security`** が PR diff を 5 カテゴリで検査:
1. Supply Chain — 依存パッケージの信頼性
2. Secrets — シークレット漏洩
3. Code Safety — 任意コード実行、パストラバーサル等
4. Entitlements — 権限変更
5. Build & Distribution — ビルドスクリプト改竄

CRITICAL → issue を in-progress に差し戻し（マージブロック）。`review_pr` と並行実行。

### Layer 3: CI/CD 防御（将来）

GitHub Actions での自動テスト、dependency audit、SBOM 生成を計画。

### アプリ配布物のセキュリティ態勢（2026-05 時点）

OSS ユーザー / 新規参加開発者向けに、現在有効な配布物側の防御を一望できる表。`README.md` の「Security」節と `CLAUDE.md` の「セキュリティ態勢」節からこの表にリンクすること（重複記述を避けるため、詳細はここに集約）。

| 領域 | 対策 | 根拠チケット | ステータス |
|---|---|---|---|
| プロセス改竄防止 | codesign `--options runtime` で Hardened Runtime を有効化（ad-hoc 署名） | KMD-26 | 有効 |
| 自動更新の真正性 | Sparkle EdDSA 公開鍵検証（`SUPublicEDKey`）、env→post-build 注入、release で必須化 | KMD-27 | 有効 |
| 鍵注入のサイレント失敗防止 | 形式バリデーション + クォート + 書き込み後の読み戻し検証（多層防御） | KMD-27 | 有効 |
| 配布スクリプトの非対称防御解消 | `generate-appcast.sh` の PLACEHOLDER/TODO/空文字拒否 + XML エスケープ | KMD-27 | 有効 |
| Sparkle.framework のバンドル | `.app/Contents/Frameworks/` への自動コピーと LC_RPATH 確保 | KMD-35 | 有効 |
| 一時ファイル / unsafeFlags / hooks の軽微修正 | `mkstemp` ベースへの移行など軽微なハードニング | KMD-29 | 有効 |
| WKWebView XSS 対策 | プレビューレンダラの追加ハードニング | KMD-28 | 検討中 |
| `Process()` 排除 | D2 を WASM 化、Diff を Pure Swift 化して外部バイナリ呼び出しを段階的に削減 | KMD-30 / KMD-31 | 検討中 |

利用者側の検証手順（`codesign --display --verbose=4` / `codesign --verify --deep --strict`）は `README.md` の「Security / 配布物の検証」を参照。リリース担当者向けの鍵生成・appcast 生成手順は [[sparkle-release]] を参照。

**設計上の不変条件**:

1. `Info.plist` に `SUPublicEDKey` の実値を直書きしない（commit 履歴に鍵を残さない）
2. `scripts/post-build.sh` の処理順序「Info.plist 上書き → 公開鍵注入 → codesign」を入れ替えない
3. 解釈系コマンド（`PlistBuddy -c` / `eval` / `bash -c` / `printf`）への外部入力は必ず形式バリデーション + クォートを通す
4. release ビルドは `KOBAAMD_SU_PUBLIC_ED_KEY` 未設定で `exit 1`（サイレント失敗の禁止）

### AI パイプライン固有のリスク

通常の開発と比較して AI 自律パイプラインでは:
- **頻度**: 30 分ごとにコードが生成されるため、攻撃面が広い
- **判断力**: AI は typosquatting パッケージを見抜けない可能性がある
- **速度**: 人間が介入する前にマージされるリスクがある

→ `review_security` が全 PR で自動実行されることで、人間不在時のリスクを軽減。

### サイレント失敗パターン（KMD-6 / KMD-27）

「ビルドは通るのに本番動作で黙って機能を無効化する」クラスのバグは、AI レビューが見落としやすい盲点。`kobaamd_review_pr` の評価軸に **「サイレント失敗の検出」** を独立観点として追加する:

| サイレント失敗パターン | 例 | 検出方法 |
|---|---|---|
| 環境変数未設定で機能無効化 | `SUPublicEDKey` 空文字でも release ビルドは通る (KMD-6) | release ビルドのみ env 必須化 + 未設定で exit 1 |
| シェル変数の裸展開 | `PlistBuddy -c "Set :Key $VAR"` で `$VAR` の空白で値が落ちる (KMD-27) | 全変数を `"$VAR"` でクォート + 形式バリデーション |
| 設定値が空文字のままマージ | 公開鍵プレースホルダーが残ったままリリース (KMD-6) | リリーススクリプトで PLACEHOLDER/TODO/空文字を拒否 |
| 検証ロジックが always-pass | 条件分岐の typo で常に true 評価 | 単体テストで失敗ケースの assert を必須化 |

KMD-27 では多層防御（形式バリデーション + クォート + 読み戻し検証）でサイレント失敗の発生路を完全に塞いだ。詳細は [[sparkle-release]] の「多層防御の設計」節。

### シェルスクリプトのクォート規約

AI 自律パイプラインで生成されるシェルスクリプトには、必ず以下のルールを適用:

1. **変数展開は必ず `"$VAR"` でクォート**
2. **解釈系コマンド（`PlistBuddy -c`, `eval`, `bash -c`, `printf`）に外部入力（env / argv / file）を渡す前に形式バリデーション**（regex / 長さチェック等）
3. **対称性チェック**: 同種の検証ロジックが他のスクリプトに存在する場合、強度を揃える（片方だけ守られている状態を作らない）

このルールは [[postmortem-patterns]] パターン 8/9 として体系化済み。

## Related

- [[autonomous-pipeline-philosophy]] — パイプラインの設計思想
- [[postmortem-patterns]] — 過去の問題からの学び（パターン 8/9/11 が本記事と関連）
- [[sparkle-release]] — KMD-27 で確立された多層防御の具体実装

## Sources

- docs/adr/0009-security-hardening.md
- docs/learnings/2026-05-01-KMD-26.md
- docs/learnings/2026-05-01-KMD-27.md
