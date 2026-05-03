# Wiki Log

操作履歴（追記専用）。

## [2026-04-30] Wiki 初期構築

- SCHEMA.md 作成（Karpathy LLM Wiki パターン準拠）
- index.md 作成（8記事のスケルトン）
- 初期記事 8件を作成（concepts 2, decisions 2, components 2, practices 2）
- ソース: ADR 0001-0008, docs/learnings/KMD-4,6,20,22, CLAUDE.md

## [2026-04-30] Architecture カテゴリ追加

- `articles/architecture/wkwebview-strategy.md` 作成（WKWebView 共存戦略とメモリ管理）
- index.md に Architecture セクション追加
- ソース: MarkdownWebView.swift, D2WebView.swift, WYSIWYGEditorView.swift, BundledJS.swift, MarkdownService.swift, ADR-0004

## [2026-04-30] D2 ダイアグラムプレビュー記事追加

- articles/components/d2-diagram-preview.md を新規作成
- index.md の Components セクションに追加
- ソース: D2Service.swift, D2WebView.swift, D2PreviewViewModel.swift, BundledJS.swift

## [2026-05-04] Wiki 参照ポリシー記事追加（KMD-49）

- `articles/practices/wiki-reference-policy.md` を新規作成（Phase 1 Prompt Caching 標準運用、Phase 移行トリガー、Opus/Sonnet/Haiku 使い分け、Haiku 必須ルール 4 項目）
- `SCHEMA.md` の「ワークフロー > Query」節を Phase 1 標準手順 + フォールバック手順 + Phase 移行トリガーに更新
- `CLAUDE.md`（gitignore 管理）にも同等の内容を「自律開発パイプライン > Wiki 参照ポリシー」と「モデル割り当て方針 > Haiku の用途」として追記
- index.md の Practices セクションに新記事を登録
- ソース: KMD-45, KMD-46（scripts/wiki/load_all.sh）, KMD-47（scripts/wiki/ask.sh）, KMD-48, KMD-49
