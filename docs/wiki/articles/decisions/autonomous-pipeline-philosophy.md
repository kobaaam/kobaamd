---
title: AI 自律開発パイプラインの設計思想
category: decisions
tags: [pipeline, linear, subagent, automation, auto-carve-out, carve-out]
sources:
  - docs/adr/0007-autonomous-pipeline-linear.md
  - CLAUDE.md
  - docs/learnings/2026-05-05-KMD-54.md
  - docs/learnings/2026-05-06-KMD-144.md
created: 2026-04-30
updated: 2026-05-06
---

# AI 自律開発パイプラインの設計思想

## Summary

kobaamd は AI エージェント群が draft → done まで自律的に開発を進める実験場。人間の承認ゲートを最小化しつつ、暴走を防ぐ安全弁を設計に組み込んだ。

## Content

### なぜ自律パイプラインか

個人開発では人間のボトルネック（レビュー待ち、優先度判断の遅延）がスループットを制限する。AI に判断を委譲できる領域を最大化し、人間は「何を作るか」と「破壊的変更の承認」のみに集中する。

### Linear を選んだ理由

GitHub Issues では状態遷移の柔軟性が不足。Linear は MCP 経由で状態遷移が API から操作でき、カスタムステータス（draft → backlog → todo → In Progress → in Review → Reviewed → Done）を定義できる。

### 人間承認ゲートの設計

1. **backlog → todo**: AI 起票には `ai-research` ラベル + Low priority が必ず付く。人間がラベル除去 or priority 変更で承認。
2. **[BREAKING] レビュー**: PR タイトルに `[BREAKING]` がある場合のみ Human in Review を経由。それ以外は AI が直接 Reviewed → Done。

この設計は「信頼の漸進的拡大」の原則に基づく。AI の判断精度が向上すれば、ゲートをさらに減らせる。

### auto carve-out フローの判断条件
<!-- llm-context: kobaamd_review_pr が「APPROVE / Reviewed 直行 / Human in Review を経由しない」と判定する具体条件と、carve-out された concern を統合チケットとして起票する判断条件。 -->

`kobaamd_review_pr` は concern を **rework / auto-carveable / human-judgment** に分類する。AI が機械的に裁ける auto-carveable concern（独立改善・別 PR が自然なもの）は別 issue を自動起票し、親 PR をブロックしない設計。

#### Reviewed 直行が成立する 3 条件

以下 3 条件をすべて満たすと、review_pr は APPROVE auto carve-out で `Reviewed` 直行を選択し、人間レビューを経由せず自動マージへ進む。

1. **PRD AC を完全充足**（全項目 pass）
2. **影響範囲が PRD 記載と一致**（PR コメントで「触れていない箇所」を明示）
3. **残 concern が `auto-carveable` 分類のみ**（rework=0, human-judgment=0, `[BREAKING]` なし）

逆に、PRD AC 充足が pass でも、影響範囲が PRD と乖離している、または concern が「仕様判断必要」に該当すると `Human in Review` に入る。実装段階で「PRD に書かれた影響範囲だけを触る」「CSI 改善は別 issue 起票で残す」を意識すると Reviewed 直行率が上がる。

KMD-144 (PR #70) はこの 3 条件を満たし、in Review → Reviewed → Done が同日内で完了した。

#### auto-carveable concern の統合チケット化

親 PR のレビューで auto-carveable な concern が複数残ったとき、1 件 1 チケットに分割すると個々が小さすぎて優先度が上がらず Backlog に放置されやすい。以下 3 条件が揃う場合、複数の concern を 1 つの統合チケットとして起票してよい。

1. **同じファイル群に閉じる**（例: KMD-144 はいずれも `kobaamd_update_wiki` 周辺）
2. **影響範囲が共通**（同じモジュール / 同じパイプラインステップ）
3. **同じレビュー観点で評価できる**（例: 「ingest プロセスの可観測性」というドメインでまとまる）

逆にこの 3 条件が揃わないなら、無理に統合せず個別起票にする（PR が肥大化して影響範囲レビューが難しくなる）。

詳細は [[postmortem-patterns]] パターン 13 / 14 を参照。

### Opus / Sonnet の使い分け

判断・創造系（PRD 作成、コードレビュー、振り返り）は Opus、機械的操作系（ビルド検証、マージ、コメント修正）は Sonnet。コストと品質のバランス。

### auto carve-out によるクリーン APPROVE 直行
<!-- llm-context: kobaamd_review_pr が auto-carveable concern を別チケットに退避することで、本 PR を block せず Human in Review を経由せずに Reviewed 直行できる運用。スループット最大化の中核機構。 -->

`kobaamd_review_pr` は concern を **rework / auto-carveable / human-judgment** に三分類する。auto-carveable（独立改善・別 PR が自然なもの）は Linear に別チケットを自動起票し、本 PR をブロックせず `Reviewed` に直行させる。

これにより、Human in Review に入るのは **本当に人間判断が必要な場合のみ**（`human-judgment` か `[BREAKING]`）に絞られ、AI が機械的に裁ける UI 磨き込み・追加機能アイデア・テスト整備の充実などは自動 carve-out で退避される。

KMD-54 の実例では auto carve-out 2 件（KMD-141 テスト整備・KMD-142 投稿失敗 observability）を起票してクリーン APPROVE 直行し、Reviewed → Done が約 4 分で完了した。carve-out 先 issue 本文には「親 KMD-XX (auto-carved-out by kobaamd_review_pr)」と「人間が本 PR で対応すべきと判断した場合は本チケットを close/revert して親を re-open する」手順を必ず含める規約になっており、carve-out のリカバリ経路が運用上担保されている（[[postmortem-patterns]] パターン 8 を参照）。

## Related

- [[multi-llm-persona]] — LLM ペルソナの役割分担
- [[prd-quality-cycle]] — PRD の品質サイクル
- [[security-hardening]] — パイプラインに組み込む多層防御の運用
- [[postmortem-patterns]] — クリーン APPROVE 直行 4 条件、auto carve-out 規約、auto carve-out フローのパターン化（パターン 13 / 14）
- [[dependency-inversion-guard]] — pipeline_weekly が依存逆順でも落ちないためのガードパターン

## Sources

- docs/adr/0007-autonomous-pipeline-linear.md
- CLAUDE.md: 自律開発パイプラインセクション
- docs/learnings/2026-05-05-KMD-54.md
- docs/learnings/2026-05-06-KMD-144.md
