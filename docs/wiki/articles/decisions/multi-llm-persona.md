---
title: マルチ LLM ペルソナ体制
category: decisions
tags: [llm, claude, codex, gemini, persona]
sources: [CLAUDE.md]
created: 2026-04-30
updated: 2026-04-30
---

# マルチ LLM ペルソナ体制

## Summary

kobaamd は Claude（設計・レビュー）、Codex CLI（実装）、Gemini（調査・ドキュメント）の 3 ペルソナ体制。各 LLM の強みに特化させ、役割混在を厳禁とする。

## Content

### 3 ペルソナの役割

| ペルソナ | LLM | 担当 |
|---------|-----|------|
| Orchestrator | Claude Opus | 統括・設計・レビュー・分析 |
| SubAgent（判断系） | Claude Opus | PRD 作成・レビュー・振り返り |
| SubAgent（機械系） | Claude Sonnet | ビルド・マージ・定型修正 |
| UI Coder | Codex CLI | SwiftUI 実装・リファクタ |
| Researcher | Gemini | 技術調査・ドキュメント生成 |

### なぜ役割を分離するか

1. **品質**: 各 LLM が得意領域に集中することで出力品質が向上
2. **監査性**: 誰が何を書いたかが明確（Claude は設計、Codex は実装）
3. **コスト**: 機械的タスクに Opus を使う無駄を排除
4. **安全性**: Claude が直接コードを書かないことで、レビューの独立性を保証

### 厳守ルール

`.swift` ファイルの新規作成・編集は **必ず Codex CLI に依頼**。Claude が直接コードを書くことは原則禁止。これはプロジェクトの開発体制の根幹。

## Related

- [[autonomous-pipeline-philosophy]] — パイプライン全体の設計思想

## Sources

- CLAUDE.md: 厳守ルール・役割分担セクション
