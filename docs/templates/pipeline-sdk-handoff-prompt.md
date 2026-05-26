# Handoff: SDK + Self-hosted Workflow Pipeline (from kobaamd, 2026-05)

このプロンプトは、kobaamd で実証した **「Anthropic SDK 直叩き + 自前 workflow primitive + persona-swapped review」** のパイプライン設計を、**他のプロジェクトの Claude Code セッションに伝えるためのハンドオフ**です。ローカル同一マシン内の別セッションが対象。kobaamd のファイル群を `Read` で取りに行けることを前提に、絶対パスで参照します。

別プロジェクトでこのプロンプトを Claude Code に貼る運用想定:

> このプロンプトを読んで、kobaamd で確立した設計を私のプロジェクトに移植してください。kobaamd のファイルは絶対パスでローカルにあるので `Read` で参照可能。Bun 等の外部参考は web で再調査して構わない。

---

## 1. What this handoff is

kobaamd（macOS ネイティブ Markdown editor、Swift / SwiftUI）の自律パイプライン (`pipeline_active` 等) を、当初は `claude -p` 経由で 30 分間隔で動かしていた。これは以下の理由で **「Anthropic SDK 直叩き + 自前 workflow primitive」に段階移行**した:

1. **2026-06-15 から Anthropic split billing** — Claude Code / Agent SDK 経由の使用が新しい credit pool ($20 Pro / $100 Max 5x / $200 Max 20x、繰越不可、API list price で metered) から引かれるようになった。`claude -p` 内部最適化は unpredictable だが、SDK 直叩きなら cache / Batch / model mixing を握れる
2. **claude -p は invocation あたり 25-50k tokens の overhead** — CLAUDE.md / agent definitions / tool definitions を毎回ロード。SDK 直叩きなら system prompt は数 KB に絞れる
3. **複数モデル混在の最適化が claude -p では効きにくい** — Haiku で classify、Sonnet で refute、Opus で戦略判定、のような混在が SDK なら自然に書ける

実測コスト比較 (kobaamd で 3 件の PoC 実験):

| 実験 | SDK 実測 | claude -p 推定 | 削減比 |
|---|--:|--:|--:|
| archive_done (Done 7 件 / stale 2 件) | $0.000957 | ~$0.051 | **53×** |
| prioritize_backlog (92 件→5 件) | $0.006424 (Haiku) | ~$0.10-0.30 | 15-30× |
| pipeline_active 1 cycle (6 step) | $0.010842 | ~$0.752 | **69×** |

詳細は kobaamd 内に保存:

- `/Users/h.kobayashi02/atelier/kobaamd/artifacts/comparison-summary.md` — 3 実験の総合まとめ
- `/Users/h.kobayashi02/atelier/kobaamd/artifacts/pipeline-comparison-2026-05-23.md` — pipeline_active 1 cycle の詳細

## 2. External references

### Bun (design inspiration)

**Bun の `.claude/workflows/lifetime-classify.workflow.js`** (約 185 行、commit `23427dbc12fdcff30c23a96a3d6a66d62fdc091d`) が設計の出発点。Zig→Rust 変換時の field lifetime 分類 (OWNED / SHARED / BORROW_PARAM / 他 11 値の enum) を 3 phase で回すパイプラインで、kobaamd の workflow primitive はこの構造をベースにしている。

**URL**: https://github.com/oven-sh/bun/blob/23427dbc12fdcff30c23a96a3d6a66d62fdc091d/.claude/workflows/lifetime-classify.workflow.js

**Primitive (Bun 実装):**

```js
phase(title: string)                              // フェーズ区切り / ロギング
pipeline(items: Array, fn: (item) => Promise)     // 順次 (array.map 相当)
parallel(tasks: Array<() => Promise>)             // thunks を並行実行
agent(prompt: string, {                            // 1 LLM call
  label: string,
  phase: string,
  schema: JSONSchema    // 構造化出力強制
})
```

**Bun が実装しているパターン (kobaamd でも踏襲)**:

1. **Agent count cap = 980 hard limit**

   ```js
   if (FILES.length + toVerify.length * 3 > 980) {
     toVerify = toVerify.slice(0, Math.floor((980 - FILES.length) / 3));
   }
   ```

   verify phase は 1 field あたり 3 agent (= 3-vote) なので、`primary + verify*3 > 980` なら verify 対象を切り詰めて適合させる。kobaamd の `workflow.mjs` も agent count cap を 980 にしている (`getAgentCount()` で照会、超えると throw)。

2. **12% sampling for high-confidence verification**

   ```js
   if (Math.random() < 0.12) toVerify.push(field);
   ```

   全 field を verify すると 980 cap を超えるので、high-confidence classification の **12% だけサンプリング**して verify に回す。**low-confidence と UNKNOWN は 100% verify** (= 全数)。kobaamd の `archive-done.mjs` はサイズが小さいので全数 verify (`low_confidence | NEEDS_REVIEW` のみ Pass2 に回す) でカバーしている。

3. **3-vote refute consensus**

   ```js
   const refutes = votes.filter(v => v.refuted).length;
   const consensus = refutes >= 2
     ? votes.find(v => v.refuted)?.correct_class
     : f.class;
   ```

   verify phase で 3 並行 agent が `{refuted: boolean, correct_class: string}` を返し、refute が 2 つ以上なら override、1 つ以下なら primary 判定を維持。kobaamd の `archive-done.mjs` は Pass2 を Sonnet で 3-vote majority に倣って実装している。

**kobaamd の workflow.mjs との設計差分**:

| 軸 | Bun | kobaamd |
|---|---|---|
| LLM 実体 | Anthropic 製 internal workflow runner (詳細非公開) | OSS `@anthropic-ai/sdk` 直接呼び出し |
| `agent()` signature | `agent(prompt, {label, phase, schema})` | `agent({prompt, schema, model, cache, systemFromFile, maxTokens})` |
| model 選択 | runner 側 default (個別 agent で指定しない設計) | 各 agent 呼び出しで `model:` 必須 (Haiku/Sonnet/Opus 明示混在) |
| cache 制御 | runner 側 (非公開) | `cache: "ephemeral"` フラグで cache_control 明示 |
| cap | 暗黙 980 (workflow file 内で逆算スライス) | `AGENT_CAP = 980` const + 超過時 throw |
| sampling | 12% 明示 | 必要に応じて呼び出し側で `Math.random()` |
| 3-vote | verify phase で並行 | Pass2 で `for (let v = 0; v < 3; v++)` |

つまり kobaamd は **Bun と同じ思想を OSS SDK でポート可能な形にした派生実装**。Bun の workflow.js を読んで「同じパターンを自分の OSS スタックで動かす」のが、別プロジェクト移植の最短ルート。

### Public sources used in design decisions

| 領域 | URL |
|---|---|
| Anthropic prompt cache (5min / 1h TTL, cache_read 0.1×) | https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching |
| Anthropic Batch API (50% off, 24h async) | https://docs.anthropic.com/en/docs/build-with-claude/batch-processing |
| OpenAI pricing (GPT-5.4 / 5.5 family) | https://platform.openai.com/docs/pricing |
| Qodo PR Benchmark (400 real PRs) | https://www.qodo.ai/blog/benchmarking-gpt-5-on-real-world-code-reviews-with-the-pr-benchmark/ |
| Composer 2.5 vs Opus 4.7 vs GPT-5.5 | https://lushbinary.com/blog/composer-2-5-vs-claude-opus-4-7-vs-gpt-5-5-coding-comparison/ |
| Greptile vs CodeRabbit catch rate | https://www.greptile.com/benchmarks |

## 3. Internal references — kobaamd files to Read

別セッションが Claude Code であれば、以下のファイルを `Read <absolute_path>` で取れる:

### Pipeline primitive と PoC 実装

| Path | 内容 |
|---|---|
| `/Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/lib/workflow.mjs` | **Workflow primitive 本体** (~120 行)。`phase / pipeline / parallel({concurrency, cap}) / agent({prompt, schema, model, cache, systemFromFile, maxTokens}) / costUsd / PRICING`。Anthropic SDK ラッパー、JSON schema 強制 (prompt + regex 抽出方式、Opus 4.7 の prefill 非対応も考慮)、ephemeral cache、agent count cap 980 |
| `/Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/ping.mjs` | SDK 経由疎通テスト最小例 (Haiku 4.5) |
| `/Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/archive-done.mjs` | **Pass1 Haiku classify → Pass2 Sonnet 3-vote refute → Pass3 TSV/archive** の典型パターン |
| `/Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/prioritize-backlog.mjs` | **同一 prompt × 3 モデル (Opus / Sonnet / Haiku)** で結果比較を artifacts に書き出す |
| `/Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/run-pipeline-active.mjs` | **pipeline_active 相当の orchestrator** (~350 行)。Step 0b 整合性チェック → 0d Backlog auto-promote → 0b' no-op early return → Phase A 既存 PR review → Phase B 1 cycle 新規実装 → Step 12 post-run snapshot。`--execute` フラグで実機モード (Linear 状態遷移 / git ops / PR 作成) |
| `/Users/h.kobayashi02/atelier/kobaamd/package.json` | `@anthropic-ai/sdk` 依存 + `"type": "module"` の最小構成 |

### Agent / role 定義 (persona swap 後)

| Path | 内容 |
|---|---|
| `/Users/h.kobayashi02/atelier/kobaamd/.claude/agents/kobaamd_implement_code.md` | **Claude Sonnet が直接 Edit/Write/Bash で実装する**。Step 10.3 に **self-review ループ** (最大 3 回、severity filter 付き) を内包 |
| `/Users/h.kobayashi02/atelier/kobaamd/.claude/agents/kobaamd_review_pr.md` | **Codex CLI に judgement を委譲** (Platform API, `gpt-5.4-mini` 等)。Model ladder + 自動選択 heuristic (volume / 論理複雑 / security trigger) + severity filter |
| `/Users/h.kobayashi02/atelier/kobaamd/.claude/agents/kobaamd_research_create_ticket.md` | Gemini 2 段クエリ (Markdown 領域 + AI-native code editor crossover) で新機能候補を発掘し Linear backlog に起票する例 |

### Templates / docs

| Path | 内容 |
|---|---|
| `/Users/h.kobayashi02/atelier/kobaamd/docs/templates/code-review-prompt.md` | **言語非依存の code review prompt テンプレ** (~250 行)。`{{PLACEHOLDERS}}` + 4 段 model ladder + severity filter + 言語別 anti-pattern 例 (Python / TS / Rust / Go / Swift) |
| `/Users/h.kobayashi02/atelier/kobaamd/docs/templates/pipeline-sdk-handoff-prompt.md` | **本ファイル** (handoff そのもの) |

### Measured results

| Path | 内容 |
|---|---|
| `/Users/h.kobayashi02/atelier/kobaamd/artifacts/comparison-summary.md` | archive_done / prioritize_backlog / pipeline_active 1 cycle の SDK vs claude -p 比較 |
| `/Users/h.kobayashi02/atelier/kobaamd/artifacts/pipeline-comparison-2026-05-23.md` | pipeline_active 1 cycle の詳細試算 (parent + subagent × 6) |
| `/Users/h.kobayashi02/atelier/kobaamd/artifacts/prioritize-backlog-*.md` | Opus / Sonnet / Haiku で同 prompt 実行した時の overlap / token / cost 表 |

## 4. Key design decisions (8 つ)

### (1) `claude -p` ではなく Anthropic SDK 直叩きに移行

理由: split billing (2026-06-15〜) で credit pool が逼迫する見込み、`claude -p` の内部 system overhead が予測不能、SDK なら cache / batch / model mixing を握れる。

実装: `/Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/lib/workflow.mjs` の `agent()` 関数。

### (2) Workflow primitive を ~120 行で自作

`phase / pipeline / parallel({concurrency, cap=980}) / agent({schema, cache, systemFromFile, maxTokens})` の 4 つ + `costUsd / PRICING` ヘルパ。Bun の workflow.js を参考。**agent count cap 980** は暴走時の防護壁として必須 (バグでループ → API 大量呼び出しの事故を防ぐ)。

### (3) JSON schema 強制は「prompt 指示 + regex 抽出」方式

prefill 方式 (assistant message を `{` で始める) は **Opus 4.7 でサポート外** (400 BadRequest)。Sonnet / Haiku は OK だが、Opus も同居させるなら prompt で「Output ONLY a JSON object」を明示 + 応答から `{...}` を regex 抽出する形が portable。`workflow.mjs` line 90 付近にそのコード。

### (4) Persona swap: Implement = Claude / Review = Codex

実装側と review 側が **同じモデル family** だと、自己肯定バイアスで「自分が書いたコードを甘く見る」傾向が出る。混ぜると別人格性が担保される。

詳細運用は `kobaamd_implement_code.md` (Claude Sonnet 直接実装) と `kobaamd_review_pr.md` (Codex Platform API 経由 judgement) に分かれている。

トリガーになった現実: **2026-05-22 に Codex の ChatGPT 週次サブスク枠が枯渇** (5/29 までリセットなし)。OpenAI Platform API ($17.95 credit balance) に経路切替し、同時に役割を入れ替えた。

### (5) Model ladder for review (4 段、自動選択 heuristic)

```
docs / wiki / コメント変更      → gpt-5-nano        ($0.0004/review)
通常 source PR (default)         → gpt-5.4-mini     ($0.005/review)
複雑 refactor / multi-file       → gpt-5.4 (full)   ($0.015/review)
CRITICAL security / 最終 BREAKING → gpt-5.5         ($0.034/review)
```

自動選択 trigger は **物量 + 論理複雑** の二段:

- **物量 trigger**: `diff_lines > 500` OR `source_files > 3`
- **論理複雑 trigger**: concurrency keywords (`actor / async / tokio / goroutine / sync.Mutex / etc.` を multi-language で grep) ≥ 3、または public/exported API signature 変更 ≥ 2、または migration / schema / build-config ファイル touch ≥ 1

詳細実装: `/Users/h.kobayashi02/atelier/kobaamd/docs/templates/code-review-prompt.md` の "Auto-selection heuristic (shell)" 節。

**重要な事実**: `gpt-5.5-nano` / `gpt-5.5-mini` は **存在しない** (404)。Flagship 系の小型 variant は GPT-5.4 family に集約。

### (6) Severity filter (Qodo PR Benchmark 知見)

GPT-5.4 family は open-ended なレビュー prompt だと **recall 42.4%** で半分以上見落とす。**明示的 severity 制約** で焦点が定まる:

```
fails      = AC 未充足 OR PRD section-8 違反 OR undeclared [BREAKING]
severity=high   = blocking 級 (broken behavior / leak / main-thread / security)
severity=medium = マージ前修正推奨 (test 不足 / 命名)
severity=low    = 報告しない (黙殺、低 severity は捨てる)

concerns 数の cap = floor(diff_lines / 50)
```

実装: `code-review-prompt.md` の "Severity filter (must obey)" 節。

### (7) Self-review loop (実装者本人による、PR 提出前)

`kobaamd_implement_code.md` の **step 10.3**。Claude (実装者) が自分の diff を critical review し、`fails=0 AND severity=high=0` になるまで自分で修正 (最大 3 回ループ)。3 回失敗時も PR は作成し、`[SELF_REVIEW_STUCK]` コメントを残して後続 Codex review に判定を委譲 (**人間 escalation はしない**)。

第一防衛線として安価に動き、本格 review (Codex) に渡す PR の品質を底上げする。

### (8) Cost-optimization layers

実測で `claude -p` 比 53× 削減できた要因の内訳:

| レイヤー | 効果 |
|---|---|
| System prompt size 削減 (CLAUDE.md ロード回避) | claude -p の 25k → SDK の 0.5k |
| Tool-use turn 削減 (LLM 判定 → host code が手続き) | 5-10 turn → 1 turn |
| Model mixing (Haiku for classify, Sonnet for refute) | Sonnet 統一比 ~3× 削減 |
| Prompt cache (cache_read 0.1×) | 同 system 再利用時 80-90% 削減 (※ 2k tokens 以上の system が必要、要件未達だと無視される) |
| Batch API (非同期 24h) | input/output 共に 50% 削減 |
| Agent count cap 980 | 暴走防止、コスト爆発を阻止 |

## 5. How to apply to YOUR project

### Phase 0: 前提確認 (~10 分)

別セッションで以下を確認:
1. Node.js >= 20 が入っている
2. `ANTHROPIC_API_KEY` を環境変数経由で取れる経路がある (`.env` 直書きは禁止、`~/.zshrc` か macOS Keychain で。Keychain 例: `security add-generic-password -a "$USER" -s anthropic-api-key -w` + `~/.zshrc` で `export ANTHROPIC_API_KEY="$(security find-generic-password -a "$USER" -s anthropic-api-key -w 2>/dev/null)"`)
3. レビュー側に Codex を使うなら `codex login status` で `Logged in using an API key` (Platform API) であること。OAuth (ChatGPT サブスク) 経由だと quota が別軸で枯渇するため `codex logout && printenv OPENAI_API_KEY | codex login --with-api-key`

### Phase 1: workflow primitive 移植 (~30 分)

```bash
# あなたのプロジェクトのルートで
mkdir -p scripts/pipeline/lib artifacts
cp /Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/lib/workflow.mjs scripts/pipeline/lib/
cp /Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/ping.mjs scripts/pipeline/

# .gitignore に node_modules/ と artifacts/ を追記
# package.json に @anthropic-ai/sdk を追加
npm init -y
npm pkg set type=module
npm install @anthropic-ai/sdk

# 疎通
node scripts/pipeline/ping.mjs
# {"ok":true, "model": "claude-haiku-4-5-...", "content_text":"pong", ...} を確認
```

### Phase 2: ユースケース 1 つを SDK 化 (~1 時間)

最も独立した「非同期で良い分類タスク」を選ぶ。kobaamd で archive_done を選んだ理由:
- 非同期で良い (Batch API 適合)
- 副作用が局所的 (Linear archive のみ、ロールバック可能)
- 効果測定が明確 (1 件あたりコストを比較しやすい)

あなたのプロジェクトでの候補例:
- 大量の issue / ticket / log の自動分類
- PR の自動ラベリング
- 古いブランチ / artifact / FF の検出と退避

実装パターン: Pass1 (Haiku で粗分類) → Pass2 (Sonnet で 3-vote refute on low-confidence) → Pass3 (実機適用)。kobaamd の `archive-done.mjs` を 1 ファイルテンプレとして読み、ticket system 部分 (lq.sh → あなたの GraphQL / REST) だけ差し替える。

### Phase 3: code review path の persona swap (~1 時間)

`/Users/h.kobayashi02/atelier/kobaamd/docs/templates/code-review-prompt.md` を `docs/templates/code-review-prompt.md` にコピーして `{{PLACEHOLDERS}}` を埋める。プロジェクト primary language が Swift 以外なら、ladder の bash heuristic の拡張子 grep を調整。

呼び出し側 (Codex CLI):

```bash
cat /tmp/review_prompt.md | codex exec --model "$MODEL" --json --output-last-message /tmp/review_result.json
```

### Phase 4: 監視と上限

- `.logs/pipeline_*.log` に毎回 1 行追記 (`ts in= out= cost= ...`)
- 週次で `awk` 集計して total cost を見る
- agent count cap 980 は **必ず維持**。事故ったときの最後の砦
- OpenAI Auto recharge は **OFF** で運用。$0 で止まる方が事故時の被害が小さい

## 6. Pitfalls — kobaamd で踏んだ穴

これを移植する側が同じ穴にハマらないように。

### (P1) 同じ branch で複数セッションが作業すると commit が混線する

kobaamd の launchd 経由 `kobaamd_implement_code` が `feature/KMD-31-*` で実装中に、別の Claude セッションが**同じ branch を checkout して別ファイルを編集 → commit** したことがあった。`reflog` で救えたが、運用上は:
- subagent / 自動ジョブが活動中の branch を人間が触らない
- 触る場合は別 branch を切る

### (P2) Opus 4.7 は assistant message prefill 非対応

JSON 強制で `messages: [..., {role: "assistant", content: "{"}]` を入れると Opus は 400。Sonnet / Haiku は OK。**全モデル動く portable な方法**は prompt 指示 + regex 抽出。

### (P3) Prompt cache は 2k+ tokens でないと無視される

`cache_control: ephemeral` を付けても、system が 442 字 (kobaamd の archive_done 初期値) では `cache_read = 0` で全く効かなかった。本番化前に system を「観点 + 例示 + format 仕様」で 2k tokens 超まで拡張すべき。

### (P4) Codex / OpenAI の認証経路は 2 系統あり、$ balance とは別の week quota がある

ChatGPT サブスク経由 (OAuth、週次リセット枠) と Platform API ($credit balance) は完全に別経路。Codex CLI が前者で認証されているとき、`platform.openai.com` の $17.95 残高は **完全に手付かずのまま** Codex が止まる。

確認: `codex login status` → `Logged in using an API key` でなければ Platform API ではない。

### (P5) `gh auth` の active account 切替を忘れると push が 403

複数 GitHub アカウント (個人 / 業務) を持っていて、`gh auth switch -u <user>` で active を切り替えて push、終わったら元に戻す。kobaamd では `gh auth switch -u kobaaam` → push → `gh auth switch -u kobaan-bst` の dance が定常化している。

### (P6) Secret 漏洩: `~/.zshrc` を `grep` してしまうと値が出力に流れる

私 (Claude) が `grep -nE 'API_KEY' ~/.zshrc` をやってしまい、OPENAI / GEMINI / LINEAR の生 key 5 つがセッション履歴に露出した事故あり。**絶対ルール**:

- `~/.zshrc` / `.env*` / `**/credentials*` / `**/*secret*` / `**/*token*` を Read/cat/grep しない
- 環境変数の存在確認は `test -n "$VAR" && echo "SET (len=${#VAR})" || echo "UNSET"` のみ
- 値を `echo "$VAR"` / `printenv VAR` / `env | grep VAR` で出さない

kobaamd memory にこのルールは恒久化済み: `~/.claude/projects/<sanitized>/memory/feedback_secret_leak.md`

### (P7) 「pipeline_active が 6 時間動かない」の判定は launchctl のログ追記先で見る

`.logs/pipeline_active.log` (subagent 活動ログ) と `.logs/kobaamd_pipeline_active.log` (`run_bundle.sh` 経由の master ログ) は **別ファイル**。後者が動いていれば pipeline は走っている (Codex 失敗で 7 秒 exit、等もここに残る)。

### (P8) Linear / ticket system の自動起票で重複を作らない

`scripts/codex/run.sh` 相当の wrapper は「同名 BLOCKED チケットが既にあれば skip」を実装する。これがないと毎回起動でブロックチケットが量産される (KMD-204 を一度作って以降 skip している実例あり)。

## 7. 何を伝えたいかの要約 (TL;DR)

- **`claude -p` で動かしている自動パイプラインは、SDK 直叩き + 自前 workflow に書き換えると 1/15-70 のコストで動く**。kobaamd で実測済み。`/Users/h.kobayashi02/atelier/kobaamd/artifacts/comparison-summary.md` を参照
- **Workflow primitive は 120 行で書ける**。Bun の workflow パターンを参考。`/Users/h.kobayashi02/atelier/kobaamd/scripts/pipeline/lib/workflow.mjs` を Read してコピー
- **Implementer と Reviewer は別ベンダーに分けると別人格性が担保される**。kobaamd は Claude 実装 + Codex review に逆転した。`/Users/h.kobayashi02/atelier/kobaamd/.claude/agents/kobaamd_implement_code.md` と `kobaamd_review_pr.md` を参照
- **Code review prompt は言語非依存テンプレ化済み**。`/Users/h.kobayashi02/atelier/kobaamd/docs/templates/code-review-prompt.md` をコピーして `{{PLACEHOLDERS}}` を埋めるだけで他言語のプロジェクトで動く
- **Self-review ループ (実装者本人) で第一防衛線**、Codex で cross-persona 本 review、で 2 段構え。`kobaamd_implement_code.md` の step 10.3
- **Pitfalls (P1〜P8)** はこの handoff の section 6 にまとめた。同じ穴を踏まないように

## 8. 別セッションへの推奨アクションリスト

1. このプロンプトの **section 3 (Internal references)** にある絶対パスを順に `Read` で取って、kobaamd の実体を確認
2. `workflow.mjs` と `code-review-prompt.md` の 2 つを最初に丸ごとコピーして、あなたのプロジェクトの語彙に置換
3. ticket system 部分 (kobaamd の `lq.sh` 経由 Linear I/O) を **あなたのプロジェクトの GraphQL / REST / GitHub Issues / etc.** に書き換える
4. 一番独立した 1 ユースケースを選んで PoC (~1-2 時間)
5. 実測コストを log に追記、SDK 版 vs `claude -p` 推定の比較レポートを書く
6. うまくいったら他のユースケースに拡張

質問が出たら、kobaamd の対応ファイル絶対パスを引用してこのセッションに戻ってきてください。
