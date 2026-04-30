# Architecture Decision Records (ADR)

kobaamd の設計上の重要な意思決定を記録する。新しい ADR を追加する際は `_template.md` を使用し、連番で採番する。

## Index

| ADR | タイトル | Status | Date |
|-----|---------|--------|------|
| [0001](0001-mvvm-observable.md) | MVVM + @Observable アーキテクチャ | accepted | 2025-12 |
| [0002](0002-nstextview-appkit-wrap.md) | NSTextView AppKit ラップによるエディタ実装 | accepted | 2025-12 |
| [0003](0003-swift-markdown-parser.md) | swift-markdown (Apple) をパーサーに採用 | accepted | 2025-12 |
| [0004](0004-mermaid-wkwebview.md) | Mermaid.js + WKWebView によるダイアグラムレンダリング | accepted | 2026-01 |
| [0005](0005-ai-multi-provider-rest.md) | AI 連携はマルチプロバイダー REST API 方式 | accepted | 2026-02 |
| [0006](0006-keychain-api-key-storage.md) | macOS Keychain による API キー保存 | accepted | 2026-02 |
| [0007](0007-autonomous-pipeline-linear.md) | AI 自律開発パイプライン + Linear 状態管理 | accepted | 2026-04 |
| [0008](0008-sparkle-auto-update.md) | Sparkle によるアプリ自動アップデート | accepted | 2026-03 |
| [0009](0009-security-hardening.md) | セキュリティ・ハードニング施策（多層防御） | accepted | 2026-04 |
| [0010](0010-split-view-layout.md) | Split View レイアウト方式 | accepted | 2025-12 |
| [0011](0011-d2-diagram-preview.md) | D2 ダイアグラムのローカルバイナリ + WKWebView プレビュー | accepted | 2026-01 |
| [0012](0012-tab-window-persistence.md) | UUID ベースのタブ状態管理 | accepted | 2026-02 |

## 運用ルール

- 新規 ADR は `docs/adr/NNNN-slug.md` で作成
- Status は `proposed` → `accepted` → 必要に応じて `deprecated` / `superseded`
- `kobaamd_create_prd` で新機能を起案する際、技術選定を伴う場合は ADR も同時に作成する
