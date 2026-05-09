---
title: マルチ LLM ペルソナ体制
category: decisions
tags: [llm, claude, codex, gemini, persona]
sources: [CLAUDE.md]
created: 2026-04-30
updated: 2026-05-09
---

# マルチ LLM ペルソナ体制

## Summary

kobaamd は Claude（設計・レビュー）、Codex CLI（実装）、Gemini（調査・ドキュメント）の 3 ペルソナ体制。各 LLM の強みに特化させ、役割混在を厳禁とする。

## Content

### 3 ペルソナの役割

| ペルソナ | LLM | 担当 |
|---------|-----|------|
| Orchestrator | Claude Opus | 統括・設計・レビュー・分析（メインセッション） |
| SubAgent（標準） | **Claude Sonnet** | PRD 作成・PR レビュー・wiki ingest・rework・実装オーケストレーション・振り返り・ビルド検証・マージ・PR コメント修正 |
| SubAgent（例外: Opus） | Claude Opus | セキュリティレビュー / 新機能リサーチ / プロンプト改善 — 誤判定の代償が大きい or 創造性が必要 or 週次低頻度の subagent のみ |
| SubAgent（バッチ） | Claude Haiku | section-context-missing 判定など、短い構造化タスクの大量実行 |
| UI Coder | Codex CLI | SwiftUI 実装・リファクタ |
| Researcher | Gemini | 技術調査・ドキュメント生成 |

### なぜ役割を分離するか

1. **品質**: 各 LLM が得意領域に集中することで出力品質が向上
2. **監査性**: 誰が何を書いたかが明確（Claude は設計、Codex は実装）
3. **コスト**: パイプラインの大半を Sonnet に倒し、Opus は誤判定リスクが高い narrow なタスクだけに絞る。バッチ系は Haiku でさらに削る
4. **安全性**: Claude が直接コードを書かないことで、レビューの独立性を保証。実装者 (Codex/gpt-5.5) と reviewer (Sonnet/Claude 系) のモデルファミリー違いで盲点の重複を防ぐ

### Sonnet 中心化の判断（2026-05-09）

当初は判断系を Opus、機械系を Sonnet で運用していたが、運用実態として:

- パイプラインの 70% 以上が judgement-heavy な subagent（review_pr / create_prd 等）で、Opus 単価がトータルコストの大半を占めていた
- judgement の中身を観察すると「PRD AC との照合 / concern 分類 (decision tree) / 規約準拠 ingest」など Sonnet で十分機能する範囲が多い
- 誤判定の代償が大きい `kobaamd_review_security`、創造性が要る `kobaamd_research_create_ticket` / `kobaamd_improve_prompt` のみ Opus を残す

KMD-119/120/121 の節約策と組み合わせ、トータル 80% 以上のコスト削減を狙う方針。

### 厳守ルール

`.swift` ファイルの新規作成・編集は **必ず Codex CLI に依頼**。Claude が直接コードを書くことは原則禁止。これはプロジェクトの開発体制の根幹。

## Related

- [[autonomous-pipeline-philosophy]] — パイプライン全体の設計思想
- [[ai-service]] — エディタ内 AI とパイプライン AI の使い分け
- [[role-dispatch]] — タスク → ペルソナ → モデル → halted フォールバックの 4 層辞書
- [[team-structure]] — コアチーム組織図（人間 PM 1 名 + AI ロール群）

## Sources

- CLAUDE.md: 厳守ルール・役割分担セクション
