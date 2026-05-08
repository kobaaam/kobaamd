---
linear: KMD-131
status: backlog
created_at: 2026-05-09
author: kobaamd_implement_code
---

# [PR-C2] source ~/.zshrc の冗長読み込み解消（subagent 冒頭で 1 回に集約）

## 1. 背景・目的

Codex 呼出のたびに `source ~/.zshrc` を heredoc 前段に置いている。Linear API でも別途 `source ~/.zshrc` を要求しており、subagent あたり 2〜4 回 source される。`~/.zshrc` には重い hook（Cargo / nvm / brew 等）が含まれるので、Bash tool の各 invocation でパースが走り、毎回 0.3〜1 秒のオーバーヘッドが発生する。

参考: `docs/learnings/2026-05-05-usage-codex-investigation.md` B1。

## 2. ターゲットユーザーとユースケース

- 自律パイプライン（pipeline_active / daily / weekly）で稼働する全 subagent / slash command
- 各 invocation の実時間短縮により、月数百回規模で実時間効果が出る

## 3. 機能要件

- 必須要件:
  - 各 subagent / slash command のドキュメントに「各 Bash invocation の冒頭で 1 回 source する」前提を明文化したセクションを追加（旧表現「subagent 冒頭で 1 回 source 済みである前提」は誤り）
  - Codex / Gemini 呼出 heredoc 内の `source ~/.zshrc` を削除（同一 Bash call 内での source 効果は後続コマンドにも届くため、heredoc 内での再 source は不要）
  - Claude Code の Bash tool は invocation ごとに独立 subshell である事実と、同一 Bash call 内での source 効果引き継ぎを明文化
- オプション要件:
  - 実装後の実時間効果を 1 サイクル分計測（best-effort、困難なら theoretical 見積りで可）

## 4. 非機能要件

- パフォーマンス: Bash tool overhead 0.3〜1 秒短縮 / invocation
- macOS との整合性: 既存パイプラインの動作互換を維持

## 5. UI/UX

該当なし（subagent / slash command ドキュメントのみの変更）

## 6. 受け入れ条件 (Acceptance Criteria)

- [x] 各 subagent / slash command のドキュメントを「各 Bash invocation の冒頭で 1 回 source する」前提に書き換え（Claude Code の Bash tool は invocation ごとに独立 subshell のため、前の Bash call の source 効果は別の Bash call に引き継がれない）
- [x] Codex / Gemini 呼出 heredoc から `source ~/.zshrc` を削除（同一 Bash call 内では source の効果が後続コマンドにも届くため heredoc 内の再 source は不要）
- [x] 上記の Bash tool 挙動（invocation 独立 / 同一 call 内引き継ぎ）を各ファイルに明文化
- [x] 実装後、実時間効果を計測 or theoretical 見積りを PRD 本体に記載（AC4）

## 7. テスト戦略

- 単体テスト: 該当なし（ドキュメント変更）
- スナップショット: 該当なし
- 手動確認: subagent / slash command の構文整合性を git diff で確認

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `.claude/agents/kobaamd_implement_code.md` | 変更 | Codex heredoc から source 削除 + 冒頭セクション追加 |
| `.claude/agents/kobaamd_fix_pr_comments.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_rework_issue.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_create_prd.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_review_pr.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_review_prd.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_research_create_ticket.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_review_security.md` | 変更 | Linear I/O セクションのみ（heredoc なし） |
| `.claude/agents/kobaamd_review_postmortem.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_validate_build.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_merge_pr.md` | 変更 | 同上 |
| `.claude/agents/kobaamd_improve_prompt.md` | 変更 | 同上 |
| `.claude/commands/kobaamd_*.md` | 変更 | Linear I/O セクションの説明文を更新 |

**共有コンテナへの注意**:
- 対象ファイルを使っている他機能:
  - `kobaamd_pipeline_active` / `kobaamd_pipeline_daily` / `kobaamd_pipeline_weekly` が各 subagent / slash command を呼び出す（バンドル経由の実行も含めて、冒頭 source の前提が満たされるか確認）
- 変更してはいけない箇所:
  - **Linear I/O ポリシー全体（CLAUDE.md）**: `LQ=./scripts/linear/lq.sh` のエイリアス規則・`mcp__linear__*` 不使用などのポリシーは触らない
  - **`scripts/codex/run.sh`**: 既存の 429 / quota 検出ロジックは変更しない
  - **`scripts/linear/lq.sh`**: API キー読み込みロジックは触らない（LINEAR_API_KEY 未設定時の error 出力は仕様）
  - **CLAUDE.md の Codex CLI 呼び出し例**: `source ~/.zshrc` を含む例文は「最初の Bash invocation で必要」を意図しており、冒頭 source ルールと整合的なので維持
  - **Swift コード一切**: 本変更は subagent ドキュメントのみで完結

### その他リスク

- 既存コードへの影響: なし（Swift コード変更なし）
- 互換性: 既存の Bash 実行は各 Bash call の冒頭で source していれば継続動作。各 Bash call の冒頭で source し忘れた場合は `LINEAR_API_KEY not set` 等のエラーになるが、これは fail-fast として望ましい（「subagent 冒頭で 1 回だけ」という誤った前提で書かれた Bash call は各 call の冒頭 source が漏れているため、修正が必要）
- 外部依存: なし

## 9. 計測・成果指標

### AC4 実測値（PR #91 実装時に計測）

zsh subshell の `source ~/.zshrc` を 5 回連続実測（warm cache、MacBook Pro M3 Pro）:

| 回 | real |
|---|---|
| 1 | 0.15s |
| 2 | 0.04s |
| 3 | 0.03s |
| 4 | 0.03s |
| 5 | 0.03s |

- 1 サイクル（pipeline_active 1 回）あたり heredoc 内の冗長 source を 5〜10 invocation 削減 × 30〜150ms ≈ **150ms〜1.5s / サイクル**
- pipeline_active は 30 分間隔（1440 cycle/月）→ 月次 **3.6〜36 分** の Bash tool overhead 削減

**重要な注訂**: invocation ごとの 1 回 source は依然として必要（Bash tool の独立 subshell 特性）。今回の最適化対象は「同一 Bash call 内での冗長 source」（heredoc 等）であり、Bash call をまたぐ source の省略ではない。

## 10. 参考資料

- `docs/learnings/2026-05-05-usage-codex-investigation.md` B1（参考章。ファイル不在時は issue 本文 KMD-131 を一次情報とする）
- CLAUDE.md「Linear I/O ポリシー」
