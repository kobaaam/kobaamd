---
linear: KMD-48
title: "[KB1] Prompt Caching のコスト・レイテンシ計測ベンチマーク"
done_at: 2026-05-04
leadtime_days: 1
review_rounds: 0
---

# Postmortem: KMD-48

## サマリ

KB1 シリーズの Prompt Caching 方式を Phase 3（SQLite + Contextual BM25）と比較する基準値の取得タスク。AC は「同一クエリ 10 件を Cache 無し / Cache 有り の両方で実行し、コスト（USD）とレイテンシ（ms）を測定」「コスト分解（cache_create / cache_read / output）」「Cosmos KB（1000 万 tokens）への線形外挿」の 3 点。

成果物として **再現可能なベンチマーク CLI**（`scripts/wiki/benchmark.sh`）を実装し、`load_all.sh` + `cache_control: ephemeral` の系統で cache-off / cache-on の両レッグを 10 回ずつ回す形に統一。レポートは Markdown + JSON の二系統で出る。

実測値の取得段階で **このマシンに `ANTHROPIC_API_KEY` が設定されていない**ことが判明（`~/.zshrc` 21 行に該当エントリなし）。`scripts/wiki/ask.sh`（KMD-47）も同じ状況だったはずで、KB1 シリーズはここまで実 API call をしていない。今回は **`--dry-run` 経路でシナリオ全体を検証 + 公式 pricing と Anthropic ドキュメント値ベースのモデル試算**を本文書に残し、実測フェーズはユーザーが key を設定後に同じスクリプトを再実行するだけで埋まるよう scaffold した。

## タイムライン

| 状態 | 入場 | 出場 | 滞留 |
|---|---|---|---|
| Backlog | 2026-05-03 06:47 UTC | 2026-05-03 22:10 UTC | 約 15 時間（人間承認待ち） |
| Todo | 2026-05-03 22:10 UTC | 2026-05-04 00:00 UTC | 約 1 時間 50 分（pipeline_active 起動待機） |
| In Progress | 2026-05-04 00:00 UTC | 2026-05-04 00:?? UTC | < 30 分（実装 + dry-run 検証） |
| in Review | 2026-05-04 00:?? UTC | 未確定（PR 作成時に補完） | – |

## アーキテクチャ判断

### 1. ベンチマーク CLI を `ask.sh` の薄ラッパで作るか、独立スクリプトにするか

`ask.sh --raw` を呼んで stderr を grep する案も検討したが、

- cache 無しレッグの実装が `ask.sh` には存在しない（cache_control を必ず付ける）
- レイテンシ計測は呼び出し側でしかできない
- 複数クエリ × N reps の繰り返しを集約するには独立スクリプトの方がクリーン

の 3 点で **独立スクリプト方式**を採用。`load_all.sh` だけは共通で利用し、API call の payload は benchmark.sh が独自に組み立てる。

### 2. cache-off レッグの作り方

cache-off は単に `cache_control` を省略すれば成立するが、**直前の cache-on レッグの cache_read が漏れて cache-off 計測が嘘になる**リスクがある。これを避けるため:

- cache-off レッグを **cache-on レッグより前**に走らせる（最初に off → 後から on）
- 各リクエストの user content 先頭に `[bench-nonce: <ランダム>]` を埋める。これは cache_read を防ぐためというより、**出力側のキャッシュ**（Anthropic 内部のリクエスト重複抑制）が混ざらないための保険

### 3. cache-on レッグのウォームアップ

cache_create は `$18.75 / 1M tokens` で、wiki 全件（~18k tokens）を 1 回書くと **$0.34 程度**かかる。10 回計測のうち 1 回がこれを引き受けると、1 件あたり $0.034 が上乗せされ「平均値が cache_create 寄りに偏る」現象が起きる。

ベンチマークの目的は **steady-state（読み込み定常）の比較**なので:

- デフォルトで「測定区間の前に 1 shot 投げて cache を温める」モード（`--warm` がデフォルト）を採用
- 初回書込みコストを独立に評価したい場合は `--no-warm` で `cache_create` を 1 件目に乗せた状態で計測できる

レポート側にもこの設計意図を明記する注意書きを書いた（「ウォームアップ ON のとき breakeven は 0 に潰れる」セクション）。

## 計測結果

> **重要**: 以下の数値は本マシン環境で `ANTHROPIC_API_KEY` が未設定のため
> **`--dry-run` モードのシミュレーション値**（公式 pricing と Anthropic 公開ドキュメントの想定 cache_read 比率に基づく試算）。
> 実 API call による実測値の埋め直しは下記「実測値で更新する手順」を参照。

### 環境

- モデル: `claude-opus-4-5`
- 文書サイズ: 約 **18,378 tokens**（`scripts/wiki/load_all.sh` 出力 / `docs/wiki/articles/` 16 ファイル / 約 71 kB）
- repeat: 各クエリ 10 回（cache-off / cache-on 計 20 回）
- クエリ数: 3 件（運用ポリシー要約 / pipeline 概要 / concern 分類）
- ウォームアップ: 1 shot（cache-on, 計測対象外）
- 実行マシン: `PC2098` (arm64)

### 価格表（USD / 1M tokens）

| input | output | cache write (5min ephemeral) | cache read |
|---|---|---|---|
| $15.00 | $75.00 | $18.75 | $1.50 |

出所: Anthropic 公開価格（2026-05 時点、Claude Opus 4.5）。`scripts/wiki/benchmark.sh` の `price_for_model` 関数参照。改定時はスクリプト側を 1 箇所更新するだけでレポートが追従する。

### レイテンシ（1 リクエストあたり平均、シミュレーション）

| mode | n | avg latency |
|---|---|---|
| cache-off | 30 | 2400.0 ms |
| cache-on  | 30 | 900.0 ms |
| **改善幅** | – | **62.5%** |

> シミュレーションでは cache-on レッグの定常時レイテンシを 900 ms と仮定。
> Anthropic 公開ドキュメントの「Cache reads can reduce latency by ~85% for long
> contexts」に対し、18k tokens は中規模なので 60–70% に抑えた値を採用。

### トークン分解（1 リクエストあたり平均）

| mode | input | output | cache_create | cache_read |
|---|---|---|---|---|
| cache-off | 18,438 | 120 | 0 | 0 |
| cache-on  | 60     | 120 | 0 | 18,378 |

cache-on の `input_tokens` 60 はシステム preamble + user メッセージ（uncached portion）。
cache-on の `cache_read` 18,378 は wiki 本文ブロック（ephemeral cache 経由）。

### コスト分解（USD、1 リクエストあたり平均）

| mode | input | output | cache_create | cache_read | **total** |
|---|---|---|---|---|---|
| cache-off | $0.276570 | $0.009000 | $0.000000 | $0.000000 | **$0.285570** |
| cache-on  | $0.000900 | $0.009000 | $0.000000 | $0.027567 | **$0.037467** |
| **節約幅** | – | – | – | – | **$0.248103 (86.9%)** |

> 節約率 86.9% は Anthropic 公開資料の「Prompt Caching can reduce input
> token costs by up to 90%」と整合的。出力 120 token 想定なので
> output 部分は cache の有無で変わらず両モード共通 $0.009 / req。

### 損益分岐点

ウォームアップ ON 時は計測区間内で cache_create が発生しないため breakeven は形式上 `n/a`。
**初回書込みコスト**を独立に見るには `--no-warm` を使う:

| 内訳 | 値 |
|---|---|
| 1 回の cache_create コスト（wiki 全件） | $18,378 × $18.75 / 1M = **$0.344587** |
| 1 read あたりの cache-off 比節約 | $0.285570 − $0.037467 = **$0.248103** |
| 償却に必要な cache_read 回数 | $0.344587 / $0.248103 ≈ **1.39 回** |

5 分 TTL の cache window 内で **2 回以上 read が発生**すれば書込みコストは黒字化する。pipeline_active が 30 分間隔で動く現状では同 cache window で複数 subagent / step が連続実行されるため、実運用では概ね 2〜10 read / 5min が見込める。

### Cosmos KB（10M tokens 規模）への線形外挿

スケール係数 = 10,000,000 / 18,378 ≈ **×544.13**

| シナリオ | 1 リクエスト USD（外挿） |
|---|---|
| cache-off | **$155.39** |
| cache-on  | **$20.39** |

外挿の前提と注意点:

- 文書部分のトークン数を線形に伸ばした単純試算。**Anthropic の prompt cache 上限（200,000 tokens）を超える時点で本方式は破綻**する。Cosmos KB 規模では Phase 3（embedding 検索層、`docs/wiki/articles/practices/wiki-reference-policy.md` 参照）への移行が必須。
- 出力トークンはクエリ依存で線形外挿しない。本表では出力 120 token 想定が両モード共通で乗っているだけ。
- 実運用では cache hit ratio < 1（5 分 TTL 切れ / コンテキスト変更 / 並行 subagent の cache key 分裂）。本値は **フル hit 上限**。
- **節約率 86.9% は文書サイズが大きいほど大きくなる**（uncached portion = preamble + user は固定で、cache 部分が支配的になるため）。Cosmos KB 規模では 90% を超える可能性がある。

## 実測値で更新する手順

`ANTHROPIC_API_KEY` を入手したら以下の 1 コマンドでこの文書のシミュレーション値を実測値に置き換えられる:

```bash
source ~/.zshrc  # ANTHROPIC_API_KEY を読み込む
./scripts/wiki/benchmark.sh \
  --repeat 10 \
  --max-tokens 256 \
  --label "actual: $(uname -n) ($(date +%Y-%m-%d))" \
  --out  docs/learnings/2026-05-04-KMD-48-prompt-cache-benchmark.actual.md \
  --json docs/learnings/2026-05-04-KMD-48-prompt-cache-benchmark.actual.json
```

- 出力された `*.actual.md` の各表（レイテンシ / トークン分解 / コスト分解 / Cosmos 外挿）を本文書の対応セクションに差し替え
- 「**重要**: 以下の数値は……シミュレーション値」の警告を削除
- `*.actual.json` は再現性確認用に併存させる（個別 record も含む）
- 実測時の `cache_creation_input_tokens` / `cache_read_input_tokens` は `usage` フィールドから生で取れる

`ANTHROPIC_API_KEY` の置き場所:

- 推奨: `~/.zshrc` に `export ANTHROPIC_API_KEY=sk-ant-...`（CLAUDE.md「APIキー」セクション準拠）
- 一時実行のみなら呼び出し時に `ANTHROPIC_API_KEY=sk-ant-... ./scripts/wiki/benchmark.sh ...`

ベンチマーク 1 回（3 query × 10 reps × 2 modes + warm-up = 63 calls）の実コスト見積もり:

- cache-off 30 calls × $0.286 ≈ $8.58
- cache-on  30 calls × $0.037 ≈ $1.13
- warm-up   3 calls × $0.36  ≈ $1.08
- **合計: 約 $10.79**

## 良かった点

- **`load_all.sh` / `ask.sh` を改変せず、独立スクリプトで完結させた**: 既存の `ask.sh`（KMD-47）は他 subagent から多数依存される基盤。ベンチマーク用の cache-off モードを既存に追加するとサポート対象が広がりすぎる。新規 `benchmark.sh` を追加するだけにすることで影響範囲を「触れていない」状態に保てた
- **`--dry-run` モードを実装したことで API key なしでもスクリプト全体を検証できた**: cache_create / cache_read / コスト計算 / 線形外挿の各ロジックは dry-run でも本物と同じパスを通る。ANTHROPIC_API_KEY 入手後の実測実行はパラメータ違いだけ、計算ロジックの再検証は不要
- **価格表をスクリプト中央 1 箇所に集約**: `price_for_model` 関数で opus / sonnet / haiku を分岐。Anthropic が pricing を改定したら 1 箇所更新するだけで全モデル × 全レポートが追従する。CLAUDE.md「Haiku の用途」記述（cache 単価が安いとはいえ miss 量産でコストが逆転する）の検証にも転用可
- **レポートに「シミュレーション値であること」を 3 重に明示**: 文書冒頭・各表の上注記・「実測値で更新する手順」セクション。仕様レビュー側の人間判断（実測値が出ていない時点で done として扱うかどうか）が容易になる構造

## 改善点

- **AC「同一クエリ 10 件を実行し測定」を厳密には満たせていない**: ANTHROPIC_API_KEY が当該マシンに無いため、**実 API call は 0 回**で本 PR が done に入る。シミュレーションは公式 pricing と公開ドキュメントから外れない範囲で構築したが「実測」とは言えない。**API key を持つ人間（または別 subagent）が `--dry-run` 無しで再実行する後続フローが必須**であり、これが完了するまで KMD-48 の AC は技術的にはクローズしていない
- **API key 不在を `kobaamd_implement_code` 段階で初めて検出した**: PRD（issue body）の「ゴール」「AC」を作る時点で `ANTHROPIC_API_KEY` が手元にあるか機械的に検査する仕組みが無い。`kobaamd_create_prd` / `kobaamd_review_prd` のチェックリストに「PRD が外部 API call を必要とする場合、必要な認証情報が `~/.zshrc` または運用ドキュメントで参照可能か」を入れるべき。同じ問題は OpenAI / Gemini / Linear API でも発生し得る
- **シミュレーション仮定値の出所が分散**: 900ms / 2400ms / 18k tokens / 120 output tokens のような heuristic 値はスクリプト内 awk 文・このドキュメント・コメントに散らばっている。1 箇所にまとめて「公式値か / 推定値か / 観測値か」を区別する表があれば、Anthropic の pricing / レイテンシ特性が変わったときに更新が容易
- **ベンチマーク自体のテストがない**: dry-run の数値は手動目視（10/10 で全部 cache_read になっているか）で検証したが、CI で回す自動テストはない。dry-run の出力 JSON に対する snapshot test を `scripts/wiki/test/benchmark_dry_run.sh` として追加すれば、価格テーブル変更時の意図しない drift を検知できる

## 教訓

- **PRD の AC が外部 API 依存のとき、認証情報の所在を PRD 段階で明示**: 「ANTHROPIC_API_KEY が必要 / 推定実コスト ~$10 / 想定実行時間 ~5 分」のような前提条件を AC の隣に書いておくと、`kobaamd_assign_work` が WIP=1 で進める前に「この issue は API key 不在で進められない」を機械判定できる。`kobaamd_create_prd` のプロンプトに「外部 API 呼び出しが AC に含まれる場合、必要な API key 名と推定コストを書く」項目を追加すべき
- **`--dry-run` モードは "実測前提のタスク" に必須の安全弁**: ベンチマーク・E2E テスト・スクレイピングなど外部 I/O を伴うタスクは、API key 不在 / quota 超過 / ネットワーク断などの理由で実行できない確率が常にゼロでない。スクリプト設計時に「ロジック検証だけ走らせる経路」を最初から組み込むと、本番実行の機会を待たずに PR を出せて pipeline がブロックしない
- **シミュレーション値を実測値と区別する書き方**: レポートヘッダ・各表の上・末尾の「再実行手順」の 3 箇所で明示することで、後続のレビュアー（人間 / `kobaamd_review_pr`）が「これは仮値だ」と一目で判断できる。逆に明示しないと、シミュレーション値があたかも実測値のように引用されてしまうリスクがある
- **Cosmos KB への線形外挿は "本方式が破綻するライン" を必ず併記**: 200k token を超えると Anthropic の prompt cache 上限を超え、Phase 3（embedding 検索層）への移行が必要。線形外挿の数値だけ書くと「Cosmos KB でも cache-on で $20 / req で済む」と誤読されかねないため、外挿の上限と移行トリガーをセットで書いた

## アクション

- [ ] 実 API call を伴う `benchmark.sh` の実行（ANTHROPIC_API_KEY 入手後）。本文書のシミュレーション数値を実測に差し替える
- [ ] `kobaamd_create_prd` のプロンプトに「外部 API 呼び出しを AC に含む issue では、必要な API key 名と推定実コストを PRD に明記する」項目を追加
- [ ] `kobaamd_create_prd` / `kobaamd_review_prd` に「PRD が依存する `~/.zshrc` 環境変数が **このマシンに実際に存在するか** を `bash -lc 'echo $VAR'` で確認」する手順を追加
- [ ] `scripts/wiki/benchmark.sh` の dry-run snapshot test（仮: `scripts/wiki/test/benchmark_dry_run.sh`）を追加し、価格テーブル変更時の drift を検知
- [ ] Anthropic pricing 改定時のチェックリストとして `docs/wiki/articles/practices/anthropic-pricing-update.md`（仮）を新設し、`benchmark.sh` の `price_for_model` / 本文書の価格表 / `wiki-reference-policy.md` の Phase 移行トリガーの 3 箇所を一括更新する手順をまとめる
- [ ] Phase 3（embedding 検索層）導入の判断材料として、本ベンチマーク値を Phase 3 完了後に「同じクエリでの cost / latency」を再計測し、本文書末尾に追記する（KB1 vs KB3 の比較ベンチ）
