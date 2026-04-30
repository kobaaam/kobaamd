# ADR-0007: AI 自律開発パイプライン + Linear 状態管理

- **Status**: accepted
- **Date**: 2026-04-01
- **Deciders**: 人間, Claude（設計）
- **Related**: ADR-0008

## Context

kobaamd を AI エージェント群が自律的に開発を進めるパイプラインの実験場とする。タスク管理、実装、レビュー、マージまでを自動化しつつ、人間の承認ゲートを保持する設計が必要。

## Decision

- **Linear** (`KMD` チーム) でタスク状態管理
- **Claude Code subagent** (`.claude/agents/*.md`) で各工程を担当
- **launchd** で 30分/日次/週次の定期実行バンドル
- 人間承認ゲートを 2箇所（backlog→todo、[BREAKING] レビュー）に限定

## Alternatives Considered

| 選択肢 | メリット | デメリット | 棄却理由 |
|---------|---------|-----------|----------|
| GitHub Issues のみ | シンプル | ステータス管理が弱い | Linear の方がフロー制御向き |
| Jira | エンタープライズ実績 | 過剰、API 複雑 | 個人開発にはオーバースペック |
| 全自動（承認ゲートなし） | 最速 | 暴走リスク | 安全性を優先 |

## Consequences

### Positive
- issue 単位でライフサイクル全体を追跡可能
- 各 subagent が専門化されておりデバッグしやすい
- 人間の判断を最小限にしつつ安全弁を確保

### Negative
- Linear MCP 接続が必須（OAuth 初回認証）
- エージェント定義の保守コスト（現在10 subagent + 21 command）
- launchd が macOS 依存

### Risks
- エージェント間の状態不整合（in-progress 残留など）
- Codex CLI のクォータ制限による実装失敗

## References

- CLAUDE.md: 自律開発パイプラインセクション
- .claude/agents/*.md, .claude/commands/*.md
