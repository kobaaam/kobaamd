# ADR 0009: セキュリティ・ハードニング施策

- **Status**: accepted
- **Date**: 2026-04-29
- **Deciders**: @kobaaam, Claude Opus
- **Related**: ADR-0007 (autonomous pipeline)

## Context

kobaamd は AI エージェントが自律的にコードを生成・コミット・マージするパイプラインを持つ。従来の人間開発以上に、以下のリスクが高まる:

1. **サプライチェーン攻撃**: AI が提案した依存パッケージに悪意あるコードが含まれる可能性
2. **シークレット漏洩**: AI が API キーやトークンをコードに埋め込む可能性
3. **権限エスカレーション**: AI が不必要な entitlement や sandbox 例外を追加する可能性

## Decision

多層防御（Defense in Depth）アプローチで、コストの低い施策から即時導入する。

### Layer 1: ローカル防御（即時導入）

| 施策 | 内容 |
|------|------|
| .gitignore 拡充 | `.env`, `*.pem`, `*.key`, `credentials.json`, `.mcp.json` 等を除外 |
| pre-commit シークレット検出 | `sk-`, `ghp_`, `AKIA`, `xoxb-` 等のパターンを正規表現でスキャン |
| pre-commit 禁止ファイル検出 | `.env`, `.pem`, `.key` 等の拡張子を持つファイルのコミットをブロック |
| hooks バージョン管理 | `scripts/hooks/` にフックを配置し、`install.sh` でシンボリックリンク |

### Layer 2: パイプライン防御（即時導入）

| 施策 | 内容 |
|------|------|
| `kobaamd_review_security` | PR diff に対する 5 カテゴリのセキュリティレビュー（Supply Chain / Secrets / Code Safety / Entitlements / Build） |
| CRITICAL → マージブロック | セキュリティレビューで CRITICAL 判定時、issue を in-progress に差し戻し |

### Layer 3: CI/CD 防御（将来）

| 施策 | 内容 |
|------|------|
| GitHub Actions | `swift build` + `swift test` を PR ごとに自動実行 |
| Dependency audit | `Package.resolved` の変更時に依存のセキュリティ監査を実行 |
| SBOM 生成 | Software Bill of Materials の自動生成 |

## Alternatives Considered

1. **GitHub Advanced Security (secret scanning)**: GitHub Enterprise 限定。OSS リポジトリでは利用不可（将来的に検討）
2. **gitleaks / trufflehog**: 外部ツール依存。現時点では正規表現ベースの自前実装で十分
3. **Sigstore / cosign**: バイナリ署名。Sparkle + Ed25519 署名で現時点は対応済み

## Consequences

### Positive
- AI が生成したコードのシークレット混入を pre-commit で即座にブロック
- サプライチェーン攻撃を PR レビュー時点で検出可能
- hooks がバージョン管理され、新しいクローンでも `install.sh` で即座にセットアップ可能

### Negative
- pre-commit のシークレット検出は正規表現ベースのため false positive の可能性あり（`--no-verify` で回避可能だが非推奨）
- `review_security` はパイプライン実行時間を増加させる（review_pr と並行実行で緩和）

## References

- OWASP Supply Chain Security
- Apple Hardened Runtime Documentation
- Sparkle Security Documentation
