---
title: ポストモーテムから学ぶ実装パターン
category: practices
tags: [postmortem, patterns, codex, testing, observability, auto-carve-out]
sources: [docs/learnings/2026-04-28-KMD-4.md, docs/learnings/2026-04-28-KMD-6.md, docs/learnings/2026-04-29-KMD-20.md, docs/learnings/2026-04-28-KMD-22.md, docs/learnings/2026-05-06-KMD-144.md]
created: 2026-04-30
updated: 2026-05-06
---

# ポストモーテムから学ぶ実装パターン

## Summary

KMD-4/6/20/22/144 の振り返りから抽出した再発防止パターン集。実装プロンプトへの反映事項を体系化。

## Content

### パターン 1: 影響範囲マップ必須化

**問題**: PRD に「変更してはいけないファイル」が未記載 → Codex がスコープ外を変更
**対策**: PRD セクション 8 に「変更禁止ファイル一覧」を必須化
**効果**: KMD-20 でリワーク 0 回を達成

### パターン 2: View → Service 直呼び禁止

**問題**: `TemplatePickerView` が `FileService()` を直接インスタンス化（MVVM 違反）
**対策**: 実装プロンプトに「View から Service を直接呼ばず ViewModel 経由」を明記
**根拠**: 既存コードの慣習（SettingsView）が新規ファイルに伝播した

### パターン 3: onAppear の非同期化デフォルト

**問題**: `onAppear` 内のファイル I/O がメインスレッドをブロック
**対策**: ファイル I/O は必ず `Task { await ... }` パターンを使用

### パターン 4: テストは実装対象を経由

**問題**: テスト名が `ensureCustomTemplateDirectory` だが、実際は FileManager を直呼びしており FileService を一切検証していなかった
**対策**: テスト名に登場するメソッドは必ずテスト内で呼び出す

### パターン 5: ID 衝突を前提にした設計

**問題**: `DocumentTemplate.id` がファイル名のみ → ビルトインとカスタムで衝突可能
**対策**: `Identifiable.id` は名前空間プレフィックス付き（例: `"builtin:"`, `"custom:"`）

### パターン 6: concern の重大度分類

**問題**: KMD-22 で concern 6件が全て同列に並び、重要度が不明
**対策**: concern を severity (high/medium/low) で分類し、high は REQUEST_CHANGES 相当に

### パターン 12: サイレント失敗予防機構の自己観測責務
<!-- llm-context: KMD-144 ingest_history.sh で導入した「lint silent skipped を観測する機構」自身がサイレント失敗するリスクと、観測機構を新規追加するときの設計責務についてのパターン。 -->

**問題**: `kobaamd_update_wiki` の lint ゲート silent skipped を検出する `scripts/wiki/ingest_history.sh check` を新規追加したが、機構自身が以下 3 重で silent fail し得た。

1. `set -u` + `trap cleanup EXIT` + `local var=""` の組み合わせで、cleanup 発火時に `comment_file: unbound variable` で死ぬ
2. 死んだ exit 1 を呼び出し側 `kobaamd_update_wiki` step 6.f が `|| true` でマスクする
3. マスクされた結果 `HISTORY_REPORT=""` となり、`grep -E '^warning='` が空一致して warning 検出機能ごと無声化する

これは [[security-hardening]] の「サイレント失敗パターン」表の「検証ロジックが always-pass」と同型の構造。**サイレント失敗を予防する機構を新規追加するときは、機構自身が同じパターンで死なないことを AC に含める**。

**対策**:

- 観測機構の出力には必須スキーマ（例: `warning=` 行が常に含まれること）を定義し、呼び出し側で assert する
- `|| true` で握り潰す前に、最低限「実行されたか」「期待行が出力に含まれるか」を確認する
- 観測機構そのもののテストに「依存コマンド失敗 / 環境変数未設定 / 不正入力」のリカバリ系シナリオを最低 1 つ含める

**出所**: KMD-144 review_pr concern (auto-carveable → KMD-146 に集約)

### パターン 13: 親 PR の auto-carveable concern を統合チケットとして起票する
<!-- llm-context: KMD-55 (PR #65) のレビューで残った 2 件の改善を、別個の小チケットではなく 1 つの統合チケット (KMD-144) として起票したケースの判断条件。 -->

**問題**: 親 PR のレビューで auto-carveable な concern が複数残ったとき、1 件 1 チケットに分割すると個々が小さすぎて優先度が上がらない。Backlog に放置されやすい。

**対策**: 以下 3 条件が揃う場合、複数の auto-carveable concern を 1 つの統合チケットとして起票してよい。

1. **同じファイル群に閉じる**（例: KMD-144 はいずれも `kobaamd_update_wiki` 周辺）
2. **影響範囲が共通**（同じモジュール / 同じパイプラインステップ）
3. **同じレビュー観点で評価できる**（例: 「ingest プロセスの可観測性」というドメインでまとまる）

逆にこの 3 条件が揃わないなら、無理に統合せず個別起票にする（PR が肥大化して影響範囲レビューが難しくなる）。

**効果**: KMD-144 では 2 件の改善を 1 PR で処理し、レビューは Reviewed 直行で 9 分（in Review → Reviewed → Done）の高速サイクルを実現した。

**出所**: KMD-55 (PR #65) review → KMD-144 (PR #70) のサイクル

### パターン 14: APPROVE auto carve-out が成立する 3 条件
<!-- llm-context: kobaamd_review_pr が「APPROVE / Reviewed 直行 / Human in Review を経由しない」と判定するための具体条件。実装フェーズで意識すると Reviewed 直行を狙いやすい。 -->

**問題**: `kobaamd_review_pr` が `Human in Review` 経由ではなく `Reviewed` 直行で判定する条件が暗黙化されており、実装側でどこまで意識すれば auto carve-out で通るかが不明だった。

**対策**: 以下 3 条件をすべて満たすと、review_pr は APPROVE auto carve-out で `Reviewed` 直行を選択する。

1. **PRD AC を完全充足**（全項目 pass）
2. **影響範囲が PRD 記載と一致**（PR コメントで「触れていない箇所」を明示）
3. **残 concern が `auto-carveable` 分類のみ**（rework=0, human-judgment=0, `[BREAKING]` なし）

逆に、PRD AC 充足が pass でも、影響範囲が PRD と乖離している、または concern が「仕様判断必要」に該当すると `Human in Review` に入る。実装段階で「PRD に書かれた影響範囲だけを触る」「CSI 改善は別 issue 起票で残す」を意識すると Reviewed 直行率が上がる。

**効果**: KMD-144 ではこの 3 条件を満たして `Reviewed` 直行 → 自動マージで完了した。リードタイムは同日内、リワーク 0 回。

**出所**: KMD-144 (PR #70) review_pr 判定経路

## Related

- [[mvvm-observable]] — パターン 2 の概念的背景
- [[prd-quality-cycle]] — パターン 1 の PRD への反映
- [[security-hardening]] — シェル変数クォート等のセキュリティ視点の再発防止 / パターン 12 の「サイレント失敗パターン」表との接続
- [[autonomous-pipeline-philosophy]] — パターン 13 / 14 の auto carve-out フローの設計意図
- [[wiki-reference-policy]] — wiki 経由で再発防止知見を引き継ぐ手順

## Sources

- docs/learnings/2026-04-28-KMD-4.md
- docs/learnings/2026-04-28-KMD-6.md
- docs/learnings/2026-04-29-KMD-20.md
- docs/learnings/2026-04-28-KMD-22.md
- docs/learnings/2026-05-06-KMD-144.md
