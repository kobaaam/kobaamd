# Security Policy / セキュリティポリシー

## Supported Versions / サポートバージョン

Only the latest release on the `main` branch is actively maintained.
`main` ブランチの最新リリースのみを積極的にメンテナンスしています。

| Version | Supported |
|---------|-----------|
| latest (main) | Yes |
| older releases | No |

## Reporting a Vulnerability / 脆弱性の報告

**Please do not report security vulnerabilities via public GitHub Issues.**
**セキュリティ上の脆弱性を GitHub の公開 Issue で報告しないでください。**

Report vulnerabilities through [GitHub Security Advisories](https://github.com/kobaaam/kobaamd/security/advisories/new).

[GitHub Security Advisories](https://github.com/kobaaam/kobaamd/security/advisories/new) から報告してください。

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- (Optional) Suggested fix

報告内容に含めてください:
- 脆弱性の説明
- 再現手順
- 想定される影響
- （任意）修正案

## Response / 対応方針

- We aim to acknowledge reports within **5 business days**.
- We will keep you informed of our progress toward a fix.
- We will credit reporters in release notes unless anonymity is requested.

- 報告から **5営業日以内** に確認の連絡を行います。
- 修正の進捗をお知らせします。
- 匿名希望でない場合、リリースノートに報告者のクレジットを記載します。

## Known Architecture Limits / 既知のアーキテクチャ上の制限

- App Sandbox is currently disabled to allow free folder-level file access. Sandbox adoption is planned for a future release.
- Some preview features (D2, diff view) spawn external processes via `Process()`. WASM/pure-Swift alternatives are under consideration.
- WKWebView previews may receive additional XSS hardening in a future release.

- App Sandbox は現在無効（フォルダへの自由なアクセスを優先）。将来のリリースで導入を検討中です。
- 一部のプレビュー（D2・差分ビュー）は `Process()` で外部バイナリを呼び出します。WASM / Pure Swift への移行を検討中です。
- WKWebView プレビューへの追加 XSS ハードニングを将来検討予定です。
