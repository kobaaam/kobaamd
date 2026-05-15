# kobaamd — Agent Operating Guide

このファイルは Codex / Claude Code / その他 LLM エージェントの共通の一次資料です。Codex の動作と Claude Code 向けの既存運用が衝突する場合は、Codex セッションでは Codex の実行制約・sandbox・subagent 仕様を優先し、既存運用は可能な限り意味を保って読み替えてください。

## Codex 優先ルール

Codex がこのリポジトリで作業する場合、親エージェントは orchestrator として振る舞い、調査・検証・小さな実装を必要に応じて subagent に委譲して、親コンテキストの肥大化と token 消費を抑えることを既定動作にします。

### Token 圧縮と Subagent 分担

**原則**: 親エージェントは、設計判断・統合・最終レビュー・ユーザーへの説明に集中します。独立して進められる調査、ログ解析、検証、限定的な実装は軽量 subagent に任せ、親には要約だけを戻します。

subagent を既定で使う場面:
- リポジトリ探索や関連ファイル調査を並列化できる
- テスト失敗・ビルドログ・差分の一次分析を独立して行える
- 変更対象ファイルが明確に分離できる
- ドキュメント、Issue、PR、ログの要約が親コンテキストを大きく消費する
- 複数の実装候補やリスクを短く比較したい

subagent を使わず親が直接扱う場面:
- 小さく、その場で完了する修正
- 次の一手が subagent の結果に完全にブロックされる調査
- アーキテクチャ判断、仕様判断、セキュリティ上の重大判断
- ユーザーが明示的に委譲や並列化を望まない場合

### Codex モデル割り当て

Codex では Claude の Opus / Sonnet / Haiku をそのまま使わず、以下に読み替えます。利用可能モデルが異なる場合は、同じ役割に最も近い軽量・標準・高性能モデルを選んでください。

| 役割 | Codex 既定 | 用途 |
|---|---|---|
| Orchestrator / Architect | `gpt-5.5`、reasoning `medium`〜`high` | 方針決定、設計、統合、難しいバグ修正、最終レビュー |
| Explorer | `gpt-5.4-mini`、reasoning `low`〜`medium` | `rg` による探索、関連ファイル特定、類似実装調査 |
| Worker | `gpt-5.4` または `gpt-5.3-codex`、reasoning `medium` | 担当ファイルが明確な小〜中規模実装 |
| Verifier | `gpt-5.4-mini`、reasoning `low` | テスト実行、失敗ログの一次分析、リスク要約 |
| Batch / Summary | `gpt-5.4-mini`、reasoning `low` | ドキュメント要約、Issue 整理、単純な構造化判定 |

### 委譲時の出力制約

Explorer / Verifier / Batch subagent には、原則として長文の説明を求めません。親に返す内容は以下に絞ります。

- 関連ファイルと見るべき行・関数
- 根拠となる観察
- 推奨する次アクション
- 不確実な点・残リスク

Worker subagent に実装を任せる場合は、必ず担当範囲を明確にします。

- 担当ファイルまたは担当モジュールを指定する
- 他の作業者がいる前提で、無関係な変更や revert を禁止する
- 最後に変更ファイル、検証コマンド、未検証リスクだけを返させる

### コンテキスト節約の実務ルール

- 巨大ファイル、生成物、ログ、外部ドキュメントは必要箇所だけ読む
- 長い調査結果は `docs/ai-handoff.md`、Issue コメント、短いメモに圧縮してから親へ戻す
- 同じ探索を親と subagent で重複実行しない
- subagent の結果は原則信頼し、親は統合に必要な最小限だけ再確認する
- 長時間自律作業では、タスク完了ごとに状態を短く要約してから次に進む

## Claude Code からの移管情報

以下は元 `CLAUDE.md` の内容です。Claude 固有の記述は Claude Code 運用の履歴・既存パイプライン定義として保持します。Codex で実行する場合は、上記の Codex 優先ルールに従って読み替えてください。

# kobaamd — Claude Code 引き継ぎ資料

## プロジェクト概要

Mac Native Markdownエディタ。

**ビジョン**: AIが生成したMarkdownを、Macで最も快適に扱えるエディタ
**技術**: SwiftUI + AppKit / macOS 14以降 / OSSリリース済み

---

## 開発体制・LLM構成

| ペルソナ | LLM | 用途 |
|---------|-----|------|
| Orchestrator / PM / Architect | **Claude Opus** (メイン) | 統括・設計・コアロジック実装・レビュー・分析 |
| SubAgent（標準） | **Claude Sonnet** | PRD作成・PRレビュー・実装オーケストレーション・wiki ingest・振り返り・rework・ビルド検証・マージ・PRコメント修正 |
| SubAgent（高判断・低頻度） | **Claude Opus** | セキュリティレビュー・新機能リサーチ・プロンプト改善（誤判定の代償が大きい/週次実行で頻度低のもののみ） |
| SubAgent（バッチ系） | **Claude Haiku** | 短い構造化タスクの大量実行（section-context-missing 判定など） |
| UI Coder / Refactor | **Codex CLI** (gpt-5.5 / ChatGPT Plus 認証) | SwiftUI実装・コード最適化 |
| Researcher / DocWriter | **Gemini** (`gemini-3.1-pro-preview`) | 調査・ドキュメント生成 |

### APIキー
- `$OPENAI_API_KEY` — `~/.zshrc` に設定済み
- `$GEMINI_API_KEY` — `~/.zshrc` に設定済み
- **必ず `source ~/.zshrc` してから使うこと**

### Codex CLI 呼び出し（実装依頼）
```bash
source ~/.zshrc

# プロンプトをパイプで渡す（推奨：特殊文字が多い場合）
cat << 'EOF' | codex exec
以下のSwift/SwiftUIコードを実装してください。

【目的】
...

【対象ファイル】
...

【変更内容】
...
EOF

# または直接プロンプトを渡す（短い場合）
codex exec "プロンプト"
```

> **注意**: `codex exec` は `~/.codex/auth.json` の `auth_mode: chatgpt`（ChatGPT Plus 認証）で動作する。デフォルトモデルは gpt-5.5。
> API キーモード（`auth_mode: apikey`）に戻す場合は `codex login` で再認証。
> ChatGPT アカウントモード（auth_mode: chatgpt）では o4-mini が使えないため注意。

### Gemini 呼び出し（調査・ドキュメント・設計相談）
```bash
source ~/.zshrc
cat > /tmp/req.json << 'EOF'
{"contents": [{"parts": [{"text": "プロンプト"}]}]}
EOF
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-preview:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @/tmp/req.json \
  | jq -r '.candidates[0].content.parts[0].text'
```
> **注意**: Geminiへのプロンプトは日本語特殊文字が含まれる場合、必ずファイル経由で渡すこと

---

## 現在のフェーズ

**Phase 0（完了）**: PRD・アーキテクチャ設計
**Phase 1（完了）**: MVP実装
**Phase 2（完了）**: 保存機能・エラーハンドリング・UX改善
**Phase 3（完了）**: OSS公開・タブ編集・スプリットビュー・Mermaid・Git・AI
**Phase 4（次）**: TreeSitter / アウトライン / PDF Export

---

## 自律開発パイプライン（WIP）

kobaamd は AI エージェント群が自律的に開発を進めるパイプラインの実験場でもある。状態管理は Linear（`kobaan` ワークスペース / `KMD` チーム）で行い、各エージェントは Claude Code の subagent として `.claude/agents/` に定義する。

### 構成

| 要素 | 配置 | 状態 |
|------|------|------|
| タスク管理 | Linear `KMD` team | 構築中 |
| コード管理 | GitHub | 既存 |
| エージェント定義 | `.claude/agents/*.md` | 10 subagent 実装済み（Opus 7 / Sonnet 3、下記計画参照） |
| スラッシュコマンド | `.claude/commands/*.md` | 20 slash command 実装済み（下記計画参照） |
| 定期実行 | `scripts/launchd/*.plist` + `install.sh` | active(30分) / daily(8:00) / weekly(月9:00) |
| PRD 格納 | `docs/prd/<KMD-XX>-<slug>.md` | テンプレートあり |
| Linear I/O | `scripts/linear/lq.sh`（self-hosted MCP 相当の単一エントリポイント） | 全 subagent / slash 移行済み |

### Linear I/O ポリシー（重要）

Linear への読み書きは **必ず** `scripts/linear/lq.sh` 経由で行う。Linear hosted MCP（`mcp__linear__*` / `.mcp.json` の linear エントリ）はもう使わない。リポジトリから `.mcp.json` も撤去済み。

接続アカウントは `$LINEAR_API_KEY`（`~/.zshrc`）に格納された **es57ster+claude@gmail.com** ／ kobaan workspace ／ KMD team。

理由:
- メインセッションでは Linear MCP（`mcp__linear__*`）が露出せず subagent 経由でしか動かなかった
- 経路を 1 本に絞ることで「メイン / subagent / launchd / ad-hoc」のどこから呼んでも同じ挙動になる
- 監査ログ（`.logs/linear_writes.jsonl`）と ID キャッシュ（`.logs/linear_cache.json`）を一箇所で管理できる

使い方の要点:
```bash
source ~/.zshrc           # LINEAR_API_KEY が必要
LQ=./scripts/linear/lq.sh

# read
$LQ issue.get KMD-XX
$LQ issue.list  --team KMD --state draft --limit 50
$LQ comment.list KMD-XX
$LQ state.list  KMD

# write（.logs/linear_writes.jsonl に自動記録）
$LQ issue.create     --team KMD --title "..." --body @/tmp/body.md --state draft --priority 4
$LQ issue.update     KMD-XX --body @/tmp/body.md --state Backlog
$LQ issue.transition KMD-XX Backlog
$LQ issue.archive    KMD-XX
$LQ comment.add      KMD-XX @/tmp/comment.md

# 検証（API call せず payload を表示）
LQ_DRY_RUN=1 $LQ issue.transition KMD-XX Backlog
```

詳細は `./scripts/linear/lq.sh help`。

新規 subagent / slash は `tools:` で `mcp__linear__*` を宣言せず `Bash` のみで済ませること。

### ステータスフロー

```
draft → backlog → todo → In Progress → in Review → Reviewed → Done
                                              ↘ Human in Review → Reviewed
```

**方針**: 逐次レビューを必須にしないことで自律パイプラインのスループットを確保する。`kobaamd_review_pr` は concern を **rework / auto-carveable / human-judgment** に分類してから遷移先を決める:

- **rework（本 PR で直すべき）** → `fail` 扱いで `In Progress` に戻し `fix_pr_comments` ループ
- **auto-carveable（独立改善・別 PR が自然）** → 自動で別 issue を起票し、親はクリーンとして `Reviewed` 直行（または `[BREAKING]` なら `Human in Review`）
- **human-judgment（仕様・設計判断が必要）** → `Human in Review` に入れて人間判断を待つ

つまり「**人間に確認してほしい判断が残っているとき**（`human-judgment` または `[BREAKING]`）だけ `Human in Review` に入る」運用。AI が機械的に裁ける concern（UI 磨き込み・追加機能アイデア・独立した改善案）は自動 carve-out で別チケットに退避され、親 PR をブロックしない。

各ステータスの意味と入退場条件:

| ステータス | 中身 | 入場経路 |
|---|---|---|
| draft | 人間の殴り書きアイデア。PRD なし | 人間が直接起票 |
| backlog | PRD（または PRD-lite）あり、着手準備済み | `/kobaamd_research_create_ticket`（AIがPRD-lite込みで直入れ）/ `/kobaamd_create_prd`（draft から昇格） |
| todo | 人間が着手承認済み | 人間判定（label `ai-research` を外す or priority を Normal 以上に上げる） |
| In Progress | coder が実装中 | coder |
| in Review | PR が出ていて AI reviewer が確認中（途中状態） | implementer / fix_pr_comments / rework_issue |
| Human in Review | 人間に確認してほしいコメントが残っている状態 | reviewer (APPROVE [BREAKING] / COMMENT concern>0 のとき) |
| Reviewed | レビュー OK、マージ準備完了 | reviewer (APPROVE 非[BREAKING] かつ concern=0 → 直行) / 人間 (Human in Review から手動遷移) |
| done | マージ済み | `kobaamd_merge_pr` (AI、自動 or 手動起動) |

### 人間承認ゲート

人間が握る判断は **2 + α 箇所**。

1. **draft 起票（任意）**: 人間が思いつきで draft に書く。研究員 AI が backlog 直入れする経路もあるので、必須ではない
2. **backlog → todo（必須）**: AI 起票時は priority `4 (Low)` が必ず付くので、人間は以下のいずれかで承認意思を示す
   - label `ai-research` を外す（付いている場合）
   - priority を `3 (Normal)` 以上に上げる
   `kobaamd_create_prd` 以降のエージェントは、これらの条件を満たさない backlog issue には触れない。
3. **Human in Review でのコメント回答（条件付き）**: AI レビューで `concern>0` または `[BREAKING]` の場合のみ `Human in Review` に入る。人間が Linear コメントで判断を返すと `pipeline_active` が新規コメントを検出して `rework_issue` ループを再開する（または人間が `Reviewed` に手動遷移してマージへ進める）。**concern も [BREAKING] もない APPROVE はこのゲートを通らず、AI が `Reviewed` → 自動マージまで進める**。
4. **マージは AI が担う**: `Reviewed → Done` は `kobaamd_merge_pr` が自動 or 手動でマージ。コンフリクトやテスト失敗時は issue を `In Progress` に戻し `kobaamd_implement_code` がリカバリする。

### メインセッション（Claude Opus）が PR を出す場合のルール

メインセッションが手動で PR を作成した場合（緊急 hotfix、infra 修正など）も同じフローに乗せる:

- 通常の subagent と同様に `kobaamd_review_pr` を回し、判定結果に応じて `Reviewed` または `Human in Review` に進める
- メインセッションが diff を作って push する PR でも、AI レビューがクリーン APPROVE なら自動マージで構わない
- **`[BREAKING]` を含む変更**（public API 削除・メジャー dep 更新・データフォーマット破壊など）は PR タイトルに `[BREAKING]` を付与し、AI レビューが必ず `Human in Review` に送るよう導く

### 命名規則

kobaamd 専用の subagent / slash command は `kobaamd_<verb>_<output>` 形式に統一する（例: `kobaamd_create_prd`、`kobaamd_research_create_ticket`）。新規追加時もこの規則に従うこと。

### エージェント実装計画

#### MUST（パイプライン中核）
- [x] **kobaamd_research_create_ticket** (subagent, **Opus**): 新機能候補をリサーチして Linear backlog に PRD-lite 起票
- [x] **kobaamd_create_prd** (subagent, **Opus**): draft の指定 issue を PRD 化して backlog に昇格（`--auto` で全件一括処理。pipeline_active から定期実行）
- [x] **kobaamd_implement_code** (subagent, **Opus**): todo issue を Codex CLI で実装し PR 作成、in-review に進める
- [x] **kobaamd_fix_pr_comments** (subagent/slash, **Sonnet**): REQUEST_CHANGES 済み PR の指摘を Codex で修正し in-review に戻す（`--auto` で全件処理。pipeline_active から定期実行）
- [x] **kobaamd_review_pr** (subagent, **Opus**): PR diff を別人格で批判レビュー、APPROVE/REQUEST_CHANGES を判定（[BREAKING] なし → Reviewed 直行）
- [x] **kobaamd_validate_build** (subagent, **Sonnet**): swift build/test 実行と結果の Linear コメント投稿
- [x] **kobaamd_merge_pr** (subagent, **Sonnet**): reviewed の issue を main にマージして done に遷移、失敗時は in-progress に戻す
- [x] **kobaamd_archive_done** (slash): done 滞留チケットを定期アーカイブ（Linear free 250 issue 制限対策）

#### SHOULD（運用上ほぼ必須）
- [x] **kobaamd_review_prd** (subagent, **Opus**): PRD を別人格で品質レビュー、Linear コメントで指摘
- [x] **kobaamd_review_security** (subagent, **Opus**): PR の diff をセキュリティ観点でレビュー（サプライチェーン・シークレット・コード安全性・権限・ビルド）。review_pr と並行実行
- [x] **kobaamd_rework_issue** (subagent, **Opus**): in Review / Human in Review の issue に付いた人間の Linear コメント（仕様フィードバック）を読み取り、PRD 更新→再実装→PR 更新を一貫実行。仕様レベルのリワークループ
- [x] **kobaamd_assign_work** (slash): todo から次の1件を選定（WIP=1 制御）
- [x] **kobaamd_detect_stale** (slash): N日以上停滞している issue を検出して通知
- [x] **kobaamd_carve_concerns** (slash): `kobaamd_review_pr` が APPROVE/COMMENT で残した concern を Linear の別チケット（Backlog / priority Low / Improvement ラベル）として退避。Human in Review の人間判断で「本 PR では対応せず別 PR で扱う」と決めた concern を分離する手段。引数として親 KMD-XX

#### COULD（運用しながら必要に応じて）
- [x] **kobaamd_summarize_changelog** (slash): done を集約してリリースノート生成
- [x] **kobaamd_report_status** (slash): 週次レポート（リードタイム・AI採用率）を生成
- [x] **kobaamd_sync_github** (slash): GitHub Issues を Linear draft に取り込む
- [x] **kobaamd_format_code** (slash): swift-format を一括実行

#### INFRA（パイプライン基盤）
- [x] **kobaamd_snapshot_state** (slash): Linear 全 issue ステータスを `.logs/pipeline_state.json` にスナップショット。pipeline_active の pre/post-run で自動実行。差分は `.logs/pipeline_transitions.log` に追記

#### FUTURE（CSI ループ用）
- [x] **kobaamd_review_postmortem** (subagent, **Opus**): done の振り返りを `docs/learnings/` に書き出す。完了時に `kobaamd_update_wiki --source <path>` を自動起動して LLM Wiki に反映
- [x] **kobaamd_improve_prompt** (subagent, **Opus**): learnings から各 subagent のプロンプト改善案を提案
- [x] **kobaamd_update_wiki** (subagent, **Opus**): `docs/learnings/` / `docs/adr/` を読み込み、`docs/wiki/articles/` の関連記事を更新もしくは新規作成して LLM Wiki を最新化（`docs/wiki/SCHEMA.md` 準拠）。`review_postmortem` 完了時 / `pipeline_weekly` 末尾 / 手動 から起動

合計: 13 subagent + 25 slash command（うち 4 つは pipeline バンドル + 1 つは基盤）。エージェントを増やすたびに、本セクションの実装計画と `.claude/agents/` を更新する。

### モデル割り当て方針

**Sonnet 中心**でパイプラインを回し、**Opus は誤判定の代償が大きい / 創造性が必要 / 低頻度** な subagent に絞り込む。**Haiku** はバッチ実行向け。トータルコストを最適化しつつ、安全性が必要な層には Opus を残す。

| 分類 | モデル | 基準 | 例 |
|---|---|---|---|
| Orchestrator（メイン） | **Opus** | `~/.claude/settings.json` で設定 | — |
| **標準 subagent** | **Sonnet** | パイプラインのほぼすべて。PRD 作成・PR レビュー・wiki ingest・rework・実装オーケストレーション（Codex 実装の指示出し）・振り返り・ビルド検証・マージ・PR コメント修正 | `kobaamd_create_prd` `kobaamd_review_pr` `kobaamd_review_prd` `kobaamd_update_wiki` `kobaamd_rework_issue` `kobaamd_implement_code` `kobaamd_review_postmortem` `kobaamd_validate_build` `kobaamd_merge_pr` `kobaamd_fix_pr_comments` |
| **例外 subagent** | **Opus** | 以下のいずれかに該当する場合のみ Opus を選択する: (1) 誤判定の代償が大きい（セキュリティ・サプライチェーン）、(2) 創造性 / 抽象推論が深く必要、(3) 実行頻度が低く（週次以下）コスト影響が小さい | `kobaamd_review_security`（誤検出の代償大）、`kobaamd_research_create_ticket`（週次・創造性）、`kobaamd_improve_prompt`（週次・深い推論） |
| **バッチ系 subagent / scripts** | **Haiku** | 短い構造化タスクの大量実行。下記の「Haiku の用途」を参照 | `kobaamd_lint_section_context` |

**新規エージェント追加時のデフォルトは Sonnet**。Opus を選ぶ場合は上記 (1)〜(3) のいずれの理由かを subagent の冒頭コメントに明記すること。レビュー / マージ / 振り返り等のパイプライン主流で Opus を選ぶのは原則禁止。

#### Haiku の用途

Haiku は **短い構造化タスクをバッチで大量に回す**用途に使う。1 件あたりの推論深度は浅くてよいが、件数が多くスループットとコストが効くケースに適する。

代表的な用途:

- **チャンク contextual prefix 生成**: wiki / コードチャンクの先頭に「このチャンクは何の文脈に属するか」を 1〜2 文で付与する処理
- **セクション単独文脈の YES/NO 判定**: 「このセクションは外部知識なしで読めるか？」のような二値判定
- **unlinked mentions の文脈一致判定**: wiki 内で `[[wikilink]]` 化されていない言及を検出し、リンク先候補との一致を判定
- **評価クエリの半自動生成**: テスト・評価セット用のクエリ候補を記事から自動抽出

**Haiku 利用時の必須ルール**:

1. **Prompt Caching を必ず併用**: `cache_control: { type: "ephemeral" }` を文書部分（system or user の static block）に付与する。Haiku は単価が安いとはいえ、cache miss を量産するとコストが逆転する
2. **バッチ処理を優先**: 1 記事内の複数チャンクは 1 セッションで連続処理する。`scripts/wiki/ask.sh` のような共通ヘルパーから呼び、セッション単位のキャッシュを活かす
3. **失敗時のフォールバック**: リトライ 3 回、最終失敗は元入力をそのまま通過させて警告を stderr に出す（処理を止めない）。Haiku は判断が浅いぶん偶発的な誤りが起こりやすいので、品質ゲートとして「失敗時は no-op に倒す」を徹底する
4. **content_hash ベースの差分処理**: 入力チャンクの内容ハッシュを記録し、変更のないチャンクは再生成しない。記事追加 / 更新のたびに全件を再処理しない

**Haiku の用途定義は KB1〜KB4 系チケット**（KMD-45 系列）で個別の subagent / scripts に展開する。具体的な Haiku 利用箇所は以下のチケットで規定:

- KB2-2 / KB2-3: チャンク contextual prefix 生成
- KB3-2 / KB3-4: セクション単独文脈判定 / unlinked mentions 判定
- KB4-2: 評価クエリの半自動生成

### 定期実行バンドル

頻度の異なるエージェント群を 3 + 1 のバンドルにまとめ、launchd で定期実行する。

| バンドル | 頻度 | 中身 |
|---|---|---|
| `/kobaamd_pipeline_active` | 30 分 | **フェーズA**: `merge_pr` → コンフリクト解消 → `review_pr ↔ fix_pr_comments`（ループ） → `rework_issue`（人間コメントあれば） → `merge_pr`<br>**フェーズB**（**最大 5 サイクルまでループ**、1 サイクル＝1 チケット完全サイクル）: `create_prd` → `review_prd`（↔再作成ループ） → `assign_work` → `validate_build` → `review_pr` + `review_security`（並行） → `merge_pr` → `review_postmortem`。todo が尽きるか Human in Review に到達したらフェーズ B 終了 |
| `/kobaamd_pipeline_daily` | 毎日 8:00 | `archive_done` → `detect_stale` → `sync_github` |
| `/kobaamd_pipeline_weekly` | 毎週月曜 9:00 | `research_create_ticket` → `report_status` → `summarize_changelog` → `improve_prompt` |
| `/kobaamd_run_pipeline` | 手動のみ | 上記 3 つを順次実行（デモ・動作確認用） |

launchd の plist は `scripts/launchd/` に配置。`./scripts/launchd/install.sh` でロード、`./scripts/launchd/uninstall.sh` で撤去。詳細は `scripts/launchd/README.md` を参照。

`pipeline_active` は `StartInterval`（最終起動からの経過秒）、daily / weekly は `StartCalendarInterval`（時刻指定）で動くため、PC が起動している前提の運用となる。常時稼働でない場合は cron-equivalent（GitHub Actions cron など）への移行を検討。

### Wiki 参照ポリシー（Prompt Caching 標準）

`docs/wiki/` は kobaamd の知識ベース（LLM Wiki）であり、subagent が設計判断・実装・レビューを行う際の一次資料となる。**wiki 全件を毎回プロンプトに投入し、Anthropic Prompt Caching でコストを抑えるのが標準運用**である（RAG / 検索層は **20万トークンを超えるまで導入しない**）。

**標準運用（Phase 1: Prompt Caching 方式）**:

- subagent は `scripts/wiki/load_all.sh`（KMD-46 で整備、`docs/wiki/articles/**/*.md` を frontmatter 付きで連結出力）の出力をプロンプトの **先頭近くの static block** に埋め込む
- API 呼び出しは `scripts/wiki/ask.sh "<query>"`（KMD-47 で整備、`cache_control: { type: "ephemeral" }` を文書部分に付与済み）経由で行う
- 文書部分は **cache_control: ephemeral** を指定し、5 分以内の再利用で Cache Hit にする。実行ログから Cache Hit / Miss を確認できる状態にしておく
- 検索層（embedding / BM25 / ベクトル DB）は **不要**。記事追加時の運用負荷を増やさない
- 新規 subagent / slash 追加時、wiki を参照する処理は上記ヘルパー経由にすること（独自に埋め込まない）

**`scripts/wiki/ask.sh` 使い方**:

```bash
source ~/.zshrc                   # ANTHROPIC_API_KEY を読み込み
./scripts/wiki/ask.sh "kobaamd の Wiki 参照ポリシーは？"

# stdin 経由（長い質問・テンプレ流し込み）
echo "Phase 移行トリガーを箇条書きで" | ./scripts/wiki/ask.sh -

# モデル指定 / トークン上限 / リトライ回数
./scripts/wiki/ask.sh --model claude-opus-4-5 --max-tokens 2048 --retries 3 "..."
```

stdout は assistant のテキスト本文のみ。stderr には `load_all.sh` の Files / Total と、Anthropic 側 `usage`（`ask.sh usage: input=… output=… cache_create=… cache_read=…`）が出る。**2 回目以降の呼び出しで `cache_read` が増え `cache_create` が 0 に近づけば Cache Hit している**サイン。失敗時はリトライ 3 回（指数バックオフ 2/4/8 秒）し、最終失敗で stderr にエラーを出して exit 1。

**Haiku ベースの lint / 判定タスク（KMD-150 以降）**: `scripts/wiki/lint.sh` のセクション単独文脈チェックなど、Haiku を使うバッチ判定タスクは **`ANTHROPIC_API_KEY` を直接使わず Claude Code subagent 経由で起動する**。例として `kobaamd_lint_section_context` subagent (`.claude/agents/`) を `claude -p --agent kobaamd_lint_section_context` で呼び出し、`scripts/wiki/lib/section-context-check.sh` から経由する経路が既定。API キー発行・配布が不要になる。詳細は `docs/wiki/articles/practices/wiki-reference-policy.md` の「1.2 Haiku ベースの lint / 判定タスクは Claude Code subagent 経由」を参照。

**Phase 移行のトリガー**:

| Phase | 状態 | トリガー |
|---|---|---|
| Phase 1（現行） | wiki 全件を Prompt Caching でプロンプトに投入 | デフォルト |
| Phase 2 | カテゴリ単位（architecture / decisions / practices 等）で分割投入 | wiki 総量が **15 万トークン**を超え、cache miss 時のコスト・レイテンシが許容外になったとき |
| Phase 3 | embedding ベース検索層 + 必要記事のみ投入 | wiki 総量が **20 万トークン**を超えたとき（Anthropic Claude のコンテキスト上限・キャッシュ単価の観点） |
| Phase 4 | 検索層 + 要約レイヤ + ホット記事の事前ロード | Phase 3 でも応答品質が劣化したとき |

`scripts/wiki/load_all.sh` は出力末尾に `# Total: ~XXkB / ~XX,XXX tokens` を stderr に出すので、定期的に総量を観測し、15 万 / 20 万トークン到達前に Phase 移行を検討する。

---

## 技術選定（確定済み）

| 領域 | 採用 |
|------|------|
| アーキテクチャ | MVVM（`@Observable`） |
| エディタ | `NSTextView` AppKitラップ |
| Markdownパーサー | `swift-markdown`（Apple製） |
| シンタックスハイライト | 正規表現ベース → TreeSitter（v2） |
| ダイアグラム | Mermaid.js（WKWebView） |
| AI連携 | REST API（マルチプロバイダー） |

---

## セキュリティ態勢（2026-05 時点）

設計判断時の前提として、以下のセキュリティ姿勢が **既に有効** であることに留意する。詳細・運用手順は [`docs/wiki/articles/practices/security-hardening.md`](docs/wiki/articles/practices/security-hardening.md) と [`docs/wiki/articles/practices/sparkle-release.md`](docs/wiki/articles/practices/sparkle-release.md) を参照。

| 項目 | 状態 | 出所 |
|---|---|---|
| Hardened Runtime（codesign `--options runtime` / ad-hoc 署名） | 有効 | KMD-26 |
| Sparkle EdDSA 公開鍵検証（`SUPublicEDKey` を env→post-build で注入、release は未設定なら exit 1） | 有効 | KMD-27 |
| シェル変数のクォート規約・形式バリデーション・読み戻し検証（多層防御） | 適用済み | KMD-27 |
| ローカル防御（pre-commit シークレット検知 / `.gitignore` 拡張） | 適用済み | security-hardening 記事 |
| `kobaamd_review_security` による PR 単位の自動レビュー | 適用済み | パイプライン |
| WKWebView 経由の XSS 対策強化 | 検討中 | KMD-28 |
| `Process()` 排除（D2 / Diff の WASM / Pure Swift 化） | 検討中 | KMD-30 / KMD-31 |

**設計時の不変条件**:
- `Info.plist` への `SUPublicEDKey` 直書き禁止（コミット履歴に鍵を残さない）
- `post-build.sh` の処理順序「Info.plist 上書き → 公開鍵注入 → codesign」を変えない
- 解釈系コマンド（`PlistBuddy -c` / `eval` / `bash -c` / `printf`）に外部入力を渡す前に必ず形式バリデーション + クォート

---

## ⚠️ 厳守ルール：役割分担（最重要）

> **このルールを守らないことは、プロジェクトの開発体制を壊すことと同義です。**
> Claudeが直接コードを書くことは原則禁止です。

### Claude が単独でやること（これだけ）
- アーキテクチャの判断・設計
- コードレビュー・方針のすり合わせ
- バグの根本原因の特定
- Codex / Gemini へのプロンプト作成と結果の取り込み

### Codex CLI に必ず依頼すること

| 作業カテゴリ | 例 |
|---|---|
| SwiftUI View の追加・変更 | TabBarView, SplitDivider, ツールチップ追加など |
| ViewModel / Service の追加・変更 | openInTab(), タブ管理メソッドなど |
| バグ修正（コード変更を伴うもの） | Mermaid修正, 段ずれ修正など |
| リファクタリング | height統一, header削除など |
| AppDelegate / App エントリポイントの変更 | WindowGroup→Window切り替えなど |

**判断基準**: `.swift` ファイルを新規作成・編集するなら → **Codex CLI に依頼**

### Gemini に必ず依頼すること
- 技術調査・選定比較
- ドキュメント生成（README, CONTRIBUTING など）
- デザイン方針の相談

---

## 作業フロー（automode用）

1. ユーザーの要求を受ける
2. **Gemini** に調査・設計相談（必要な場合）
3. Claude がアーキテクチャを決定・Codexへのプロンプトを設計
4. **Codex CLI** に実装を依頼し、出力をレビューしてファイルに反映
5. ビルド確認（`swift build && ./scripts/post-build.sh && open .build/kobaamd.app`）
6. APIキー・秘密情報は絶対に出力しない

---

## ⚠️ PR ルール（厳守）

> **1タスク = 1PR。巨大PRは禁止。**

### PR を出すタイミング（区切り）
- 1つの機能・修正が完成してビルドが通った直後
- セッションをまたぐ前（引き継ぎの前に必ず PR or commit）
- ユーザーに「動作確認して」と伝える前

### ブランチ運用
- `feature/<KMD-XX>-<slug>` 形式でタスクごとにブランチを切る
- main への直接 push は pre-push hook でブロック済み
- 1ブランチに複数の無関係な変更を混ぜない

### PR の単位（目安）
| 変更の種類 | PR の粒度 |
|---|---|
| バグ修正 | 1修正 = 1PR |
| 新機能 | 1機能 = 1PR（UI と Logic が大きければ分割） |
| リファクタリング | 動作変更を伴わないものだけまとめて OK |
| 削除 | 削除 + 代替実装は同一 PR でよい |

---

## 行動原則（Karpathy Guidelines）

### 1. Think Before Coding
コードを書く前に問題を理解する。

### 2. Simplicity First
最もシンプルな解決策を選ぶ。

### 3. Surgical Changes
変更は最小限・ピンポイントに。

### 4. Goal-Driven Execution
ゴールから逆算して行動する。
