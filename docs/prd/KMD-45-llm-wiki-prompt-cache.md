---
linear: KMD-45
status: completed
created_at: 2026-05-04
author: kobaamd_implement_code (Claude Opus 4.7)
---

# [KB1] LLM-Wiki を prompt-cache 利用レベルまで引き上げる（エピック完了 PRD）

> 本 PRD は **エピック完了の集約ドキュメント**として後追いで作成された。
> 個別 AC は子チケット KMD-46 / KMD-47 / KMD-48 / KMD-49 で既に達成・main マージ済みであり、
> 本 PR はそれらの完了状態を Linear エピック (KMD-45) と整合させ、正規ワークフロー
> (branch → PR → review → merge → done) に乗せて監査ログを残す目的で開く。

## 1. 背景・目的

kobaamd wiki (`docs/wiki/`) は推定 7 万トークン規模で、Anthropic Contextual Retrieval 記事の
「20 万トークン未満なら RAG 不要、プロンプトに丸投げ」基準内に余裕で収まる。
検索エンジン / ベクトル DB を入れる前に、まず **Prompt Caching で全件投入方式**を確立し、
subagent / メインセッション / 手動呼び出しのどこからでも wiki 全件を Prompt Caching 付きで
Claude API に投げられる状態を作ることが本エピックの目的。

詳細な運用方針は `CLAUDE.md` の「Wiki 参照ポリシー（Prompt Caching 標準）」セクションを参照。
要点を以下に再掲する:

- subagent は `scripts/wiki/load_all.sh` の出力をプロンプトの先頭近くの static block に埋め込む
- API 呼び出しは `scripts/wiki/ask.sh "<query>"` 経由
- 文書部分は `cache_control: ephemeral` を指定し、5 分以内の再利用で Cache Hit にする
- 検索層（embedding / BM25 / ベクトル DB）は Phase 1 では不要

## 2. ターゲットユーザーとユースケース

- **subagent 群**: 設計判断・実装・レビューを行う際、wiki を一次資料として参照する
- **メインセッション (Claude Opus)**: アーキテクチャ判断や設計相談で wiki を引きたいとき
- **人間 (オペレータ)**: ad-hoc に wiki に問い合わせたいとき (`./scripts/wiki/ask.sh "..."`)

## 3. 機能要件

### 必須要件（全て子チケットで達成済み）

1. wiki 全件を 1 つのテキストに連結して標準出力するスクリプトの提供
2. subagent から wiki 全件参照が必要な時に呼べる単一エントリポイントのヘルパー
3. Prompt Caching の `cache_control` 指定が正しく効いていることをログで検証可能
4. コスト・レイテンシのベンチマーク数値を `docs/learnings/` に記録
5. `CLAUDE.md` / `docs/wiki/SCHEMA.md` に運用方針を明記

### オプション要件

- Phase 移行トリガーの定義（15 万 / 20 万トークン）— `CLAUDE.md` に記載済み

## 4. 非機能要件

- **パフォーマンス**: 2 回目以降の `ask.sh` 呼び出しで Cache Hit (`cache_read > 0` / `cache_create ≈ 0`) を確認できること
- **アクセシビリティ**: N/A（CLI ツール）
- **macOS との整合性**: bash + curl + jq のみで動作。追加ランタイム不要

## 5. UI/UX

CLI のみ。利用例:

```
$ source ~/.zshrc
$ ./scripts/wiki/ask.sh "kobaamd の Wiki 参照ポリシーは？"
（assistant 本文が stdout）
（stderr に load_all.sh の Files / Total と Anthropic usage が出る）

$ echo "Phase 移行トリガーを箇条書きで" | ./scripts/wiki/ask.sh -

$ ./scripts/wiki/ask.sh --model claude-opus-4-5 --max-tokens 2048 --retries 3 "..."
```

## 6. 受け入れ条件 (Acceptance Criteria)

子チケットの完了状況マッピング:

| AC | 内容 | 子 issue | 状態 | 主要コミット / PR |
|---|---|---|---|---|
| AC1 | `scripts/wiki/load_all.sh` が存在し、wiki 全件を 1 つのテキストに連結して標準出力する | KMD-46 | Done | `3fd9d0f` (#49) |
| AC2 | subagent から wiki 全件参照が必要な時に呼べるヘルパー (`scripts/wiki/ask.sh`) が定義される | KMD-47 | Done | `4a4b49a` (#50) |
| AC3 | Prompt Caching の `cache_control` 指定が正しく効いていることをログで確認できる | KMD-47 | Done | `4a4b49a` (#50) — `ask.sh usage: input=… output=… cache_create=… cache_read=…` を stderr に出力 |
| AC4 | コスト・レイテンシのベンチマーク数値が `docs/learnings/` に 1 件残る | KMD-48 | Done | `4e183bd` (#54) — `docs/learnings/2026-05-04-KMD-48-prompt-cache-benchmark.md` |
| AC5 | `CLAUDE.md` / `docs/wiki/SCHEMA.md` に「wiki 参照は Prompt Caching 方式で行う」運用方針が明記される | KMD-49 | Done | `b599cd3` (#48) |

全 AC 達成済み。エピック単位の追加実装は不要。

## 7. テスト戦略

- **単体テスト**: 各子チケットで個別に検証済み
- **スナップショット**: N/A（CLI / docs のみ）
- **手動確認**:
  - `./scripts/wiki/ask.sh "..."` を 2 回連続で叩き、stderr の `cache_read` が 2 回目に増えることを目視
  - `docs/learnings/2026-05-04-KMD-48-prompt-cache-benchmark.md` に数値が記録されていること

## 8. 想定リスク・依存

### 影響範囲マップ

本 PR は **docs only**。コードベースへの変更は一切なし。

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `docs/prd/KMD-45-llm-wiki-prompt-cache.md` | 追加 | 本 PRD（エピック完了集約） |

**共有コンテナへの注意**:
- 対象ファイルを使っている他機能: なし（新規 PRD ファイル）
- 変更してはいけない箇所:
  - `scripts/wiki/load_all.sh` / `scripts/wiki/ask.sh` / `scripts/wiki/benchmark.sh` の実装
  - `CLAUDE.md` の「Wiki 参照ポリシー」セクション
  - `docs/wiki/SCHEMA.md`
  - `docs/learnings/2026-05-04-KMD-48-prompt-cache-benchmark.md`
  - 既存 PRD / Sources / Tests 配下

### その他リスク

- **既存コードへの影響**: なし（docs のみ）
- **互換性**: 影響なし
- **外部依存**: 既存の `ANTHROPIC_API_KEY`（`~/.zshrc`）に変更なし

## 9. 計測・成果指標

Phase 移行トリガー（`CLAUDE.md` 「Wiki 参照ポリシー」より）:

| Phase | 状態 | トリガー |
|---|---|---|
| Phase 1（現行） | wiki 全件を Prompt Caching でプロンプトに投入 | デフォルト |
| Phase 2 | カテゴリ単位で分割投入 | wiki 総量が **15 万トークン**を超え、cache miss 時のコスト・レイテンシが許容外になったとき |
| Phase 3 | embedding ベース検索層 + 必要記事のみ投入 | wiki 総量が **20 万トークン**を超えたとき |
| Phase 4 | 検索層 + 要約レイヤ + ホット記事の事前ロード | Phase 3 でも応答品質が劣化したとき |

`scripts/wiki/load_all.sh` は出力末尾に `# Total: ~XXkB / ~XX,XXX tokens` を stderr に出すため、
定期的に総量を観測し、15 万 / 20 万トークン到達前に Phase 移行を検討する。

## 10. 参考資料

- 子チケット: KMD-46 / KMD-47 / KMD-48 / KMD-49（全て Done / merged）
- `CLAUDE.md` 「Wiki 参照ポリシー（Prompt Caching 標準）」セクション
- `docs/wiki/SCHEMA.md`
- `docs/learnings/2026-05-04-KMD-48-prompt-cache-benchmark.md`
- Anthropic Contextual Retrieval 記事 (https://www.anthropic.com/news/contextual-retrieval)
- Anthropic Prompt Caching ドキュメント (https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
