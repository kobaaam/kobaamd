---
description: Swift コードに対して swift-format / lint を手動一括実行（特定ディレクトリ対象など）
model: sonnet
---

kobaamd の Swift ソースに対して `swift-format` を手動で一括実行してください。

> **注**: 通常の開発サイクルでは自動化済み:
> - **実装後フォーマット** → `pipeline_active` ステップ 8a で自動適用
> - **日次 lint チェック** → `pipeline_daily` ステップ 4 で自動検出
>
> この手動コマンドは、特定ディレクトリのみ整形したい場合や、パイプライン外で即座に実行したい場合に使用。

引数: `$ARGUMENTS`
- 期待形式: なし、または `--check` で差分のみ表示・実行しない、または `--target <path>` で特定ディレクトリ

事前確認:
- `swift-format` コマンドが使えること（Xcode 同梱）
- main ブランチ直接編集にならないよう、現在のブランチを確認

実行手順:
1. 現在のブランチが main の場合は中止
2. 対象ディレクトリ: デフォルト `Sources/`、`--target` 指定があればそれ
3. `swift-format format -i -r <target>` を実行（in-place で再帰）
4. `--check` なら `swift-format lint -r <target>` だけ実行し差分表示
5. 変更ファイル数をカウント、git status で確認
6. 自動コミットはしない（人間レビュー前提）

完了後の報告:
- 対象ディレクトリ
- フォーマット変更されたファイル数
- 主な変更カテゴリ（インデント・改行・空白など）
- 次のアクション: `git diff` で確認、問題なければコミット
