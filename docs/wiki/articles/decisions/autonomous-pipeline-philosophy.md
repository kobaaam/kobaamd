---
title: AI 自律開発パイプラインの設計思想
category: decisions
tags: [pipeline, linear, subagent, automation]
sources: [docs/adr/0007-autonomous-pipeline-linear.md, CLAUDE.md]
created: 2026-04-30
updated: 2026-04-30
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

### Opus / Sonnet の使い分け

判断・創造系（PRD 作成、コードレビュー、振り返り）は Opus、機械的操作系（ビルド検証、マージ、コメント修正）は Sonnet。コストと品質のバランス。

## Related

- [[multi-llm-persona]] — LLM ペルソナの役割分担
- [[prd-quality-cycle]] — PRD の品質サイクル

## Sources

- docs/adr/0007-autonomous-pipeline-linear.md
- CLAUDE.md: 自律開発パイプラインセクション
