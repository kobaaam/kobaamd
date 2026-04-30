---
title: セキュリティ・ハードニング（多層防御）
category: practices
tags: [security, supply-chain, secrets, pre-commit, pipeline]
sources: [docs/adr/0009-security-hardening.md]
created: 2026-04-29
updated: 2026-04-29
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

### AI パイプライン固有のリスク

通常の開発と比較して AI 自律パイプラインでは:
- **頻度**: 30 分ごとにコードが生成されるため、攻撃面が広い
- **判断力**: AI は typosquatting パッケージを見抜けない可能性がある
- **速度**: 人間が介入する前にマージされるリスクがある

→ `review_security` が全 PR で自動実行されることで、人間不在時のリスクを軽減。

## Related

- [[autonomous-pipeline-philosophy]] — パイプラインの設計思想
- [[postmortem-patterns]] — 過去の問題からの学び

## Sources

- docs/adr/0009-security-hardening.md
