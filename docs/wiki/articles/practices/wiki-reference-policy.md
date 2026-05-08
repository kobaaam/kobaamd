---
title: Wiki 参照ポリシー（Prompt Caching 標準運用）
category: practices
tags: [wiki, prompt-caching, anthropic, haiku, sonnet, opus, knowledge-base]
sources: [docs/wiki/SCHEMA.md, KMD-45, KMD-46, KMD-47, KMD-48, KMD-49, KMD-121, KMD-150, KMD-152, KMD-154]
created: 2026-05-04
updated: 2026-05-09
---

# Wiki 参照ポリシー（Prompt Caching 標準運用）

## Summary

kobaamd の subagent / scripts は `docs/wiki/` を一次資料として参照する。標準運用は **wiki 全件を Anthropic Prompt Caching でプロンプトに投入する Phase 1 方式**。RAG / 検索層は wiki 総量が 20 万トークンを超えるまで導入しない。あわせて Opus / Sonnet / Haiku の使い分け方針を Haiku 観点まで拡張して規定する。

## Content

### 1. 標準運用（Phase 1: Prompt Caching）

- subagent は `scripts/wiki/load_all.sh`（KMD-46 で整備、`docs/wiki/articles/**/*.md` を frontmatter 付きで連結出力）の出力をプロンプトの **先頭近くの static block** に埋め込む
- API 呼び出しは `scripts/wiki/ask.sh "<query>"`（KMD-47 で整備、`cache_control: { type: "ephemeral" }` を文書部分に付与済み）経由で行う
- 文書部分は **cache_control: ephemeral** を指定し、5 分以内の再利用で Cache Hit にする。実行ログから Cache Hit / Miss を確認できる状態にしておく
- 検索層（embedding / BM25 / ベクトル DB）は **不要**。記事追加時の運用負荷を増やさない
- 新規 subagent / slash 追加時、wiki を参照する処理は上記ヘルパー経由にすること（独自に埋め込まない）

#### 1.1 `scripts/wiki/ask.sh` の使い方

KMD-47 で整備した CLI ヘルパー。`docs/wiki/articles/**/*.md` を 1 つの static block に連結し、Anthropic Messages API へ Prompt Caching 付きで POST する。

```bash
source ~/.zshrc                                  # ANTHROPIC_API_KEY を読み込み
./scripts/wiki/ask.sh "Wiki 参照ポリシーは？"

# stdin 経由（長い質問・テンプレ流し込み）
echo "Phase 移行のトリガーを箇条書きで" | ./scripts/wiki/ask.sh -

# モデル指定 / トークン上限 / リトライ回数
./scripts/wiki/ask.sh --model claude-opus-4-5 --max-tokens 2048 --retries 3 "..."

# raw レスポンスが必要な場合（運用観測・デバッグ用）
./scripts/wiki/ask.sh --raw "..." | jq '.usage'
```

挙動:

- **stdout**: assistant のテキスト本文のみ（`--raw` 指定時は JSON 全体）
- **stderr**: `load_all.sh` の `# Files: N` / `# Total: ~XXkB / ~XX,XXX tokens` と、Anthropic 側 `usage` を整形した行
  - `ask.sh usage: input=… output=… cache_create=… cache_read=…`
- **Cache Hit / Miss の見方**: 初回は `cache_create > 0`, `cache_read = 0`。**5 分以内に再呼び出しすれば `cache_read` がほぼ wiki 全量、`cache_create` は 0** になる。これが Cache Hit のサイン
- **失敗時**: 指数バックオフ（2/4/8 秒）でリトライ最大 3 回。すべて失敗で stderr にエラー出力 + exit 1。レスポンス本文の先頭 2KB を診断用に表示

設計上の制約:

- 文書部分は `system: [{ type: "text", text: "<wiki>", cache_control: { type: "ephemeral" } }]` の構造で送る。**user メッセージ側に wiki を入れない**（user 側に置くと cache 境界が壊れる）
- `ANTHROPIC_API_KEY` 必須。未設定なら exit 1（OAuth / chatgpt 認証は使わない、API キーモードのみ）
- 検索層（embedding / BM25）に切り替えるロジックは含まない。Phase 1 専用（Phase 移行のスケジュールは下記）

#### 1.1.1 subagent からの参照は ask.sh 経由が標準（Read 直読みは限定用途）

KMD-121 以降、subagent (`kobaamd_create_prd` / `kobaamd_review_pr` / `kobaamd_review_prd` / `kobaamd_review_security` ほか) の wiki 参照ステップは **`./scripts/wiki/ask.sh` 経由を標準** とする。Read による個別記事の直読みは以下のケースに限る:

- ask.sh の回答で挙がった article path のうち、**特定記事 1 件を精査する**必要があるとき
- 短い節を引用する目的で位置を厳密に確認したいとき
- 認証・ネットワーク不調で ask.sh が使えない一時的フォールバック

ask.sh 経由を標準とする理由:

- Prompt Caching によって 2 回目以降の呼び出しは `cache_read` が wiki 全量に近づき、cost ≈ 1/10 / レイテンシ短縮（KMD-48 ベンチマーク）
- subagent ごとに記事候補を手選びすると、記事追加時に subagent プロンプトを更新し続ける運用負荷が発生する。ask.sh は wiki 全量を毎回 LLM に渡すので、新規記事を追加するだけで自動で参照対象になる
- 観点抽出（postmortem パターン・該当 decisions・関連 components）を一度の API 呼び出しで横断できる

運用上の確認:

- subagent 起動時、ask.sh の stderr に出る `ask.sh usage: input=… output=… cache_create=… cache_read=…` を観測する
- 1 サイクル内で `cache_read` が増えていれば期待通り（cache_create は初回のみ）
- ask.sh の preamble はレスポンスに article path を必須で含めるよう設計されているため、subagent はその path を観点反映時に引用する

#### 1.2 Haiku ベースの lint / 判定タスクは Claude Code subagent 経由（KMD-150 以降）

`docs/wiki/articles/` の lint や、KB3 系の YES/NO 判定タスクのように **Haiku を使う場面では `ANTHROPIC_API_KEY` を直接利用せず、Claude Code subagent 経由で起動する**。

- 既定経路: `claude -p --agent <name>`（`--agent` で `.claude/agents/*.md` の subagent 定義を読み込み、`model: haiku` のフロントマターで Haiku を指定）
- 例: `scripts/wiki/lib/section-context-check.sh` は `kobaamd_lint_section_context` subagent を呼び、内部で `claude -p --agent kobaamd_lint_section_context` を起動する
- これにより、API キーの発行・配布・ローテーションが不要になり、Claude Code 認証だけで Haiku 判定が回る
- レガシー経路（`scripts/wiki/lint.sh --legacy-api` 等）は移行期間中のフォールバック。新規スクリプトでは使わない

設計指針:

- subagent の `tools:` は最小限に絞る（典型は `Read, Bash`）。これにより外部 context が混入せず、判定の再現性が安定する
- subagent の出力は **stdout に NDJSON、stderr に統計サマリ** に分離する。呼び出し元の shell スクリプトは stdout から JSON 行だけ取り出して集計する
- `claude -p` の出力に prose が混入する可能性があるため、呼び出し元では `jq -e .` でパース可能かつ期待する `rule` を含む行のみを抽出する防御を入れる

**最小権限の allowlist で起動する（KMD-152 以降）**:

- subagent を起動するときは `claude -p --allowedTools "Read" "Bash(<cmd>:*)" ...` のように **明示的な allowlist** を指定し、`--permission-mode bypassPermissions` は使わない
- subagent 定義ファイル（`.claude/agents/<name>.md`）の frontmatter `tools:` だけでは不十分。Claude Code の現行仕様では frontmatter は `Read, Bash` のような粗い宣言しかできず、`Bash` を許すと内部で `curl` / `ssh` / `rm -rf` 等の任意コマンドが通る
- 実装パターン: subagent 側のドキュメント（`## 制約・厳守事項`）に「呼ばれることを想定するコマンドのリスト」を明記し、呼び出し元 shell スクリプトの `--allowedTools` 配列にも同じリストを書く。両者がドリフトすると subagent 起動が失敗するので、運用 PR では必ず両方を同時更新する
- 攻撃モデル上の意義: AI 自律パイプライン（30 分間隔）で wiki 記事を AI が編集する KB3 系設計と組み合わさると、プロンプトインジェクション経由で任意コマンド実行に直結する経路が理論上開く。Bash allowlist を絞っておくことで、注入が成功しても **lint subagent が叩ける道具が `python3` / `jq` / `shasum` / `git rev-parse` / `mkdir` / `mv` / `cat` / `printf` / `awk` / `sed` に限定される**
- 実装例: `scripts/wiki/lib/section-context-check.sh` の `run_subagent()`、および `.claude/agents/kobaamd_lint_section_context.md` の `## 制約・厳守事項` を参照

Phase 移行のトリガー条件・運用手順は次節と共通。

#### 1.3 2 経路（legacy / subagent）の判定差分検証（KMD-154）

**結論**: KMD-150 で導入された subagent 経路は、KMD-152 の最小権限化以降 **本番で一度も成功していなかった**（CLI 引数解釈バグで全呼び出しが失敗）。KMD-154 でこのバグを発見・修正し、subagent 経路が現実に動くようになった上で、両経路の判定差分検証を行った。

**実証データ（subagent 経路、2026-05-09、cache 空）**:

- 対象: `docs/wiki/articles/**/*.md` 全 19 件
- ルール 4（section-context-missing）の violation: **0 件**
- 1 件あたり所要時間: 約 3〜5 分（Haiku セッションの起動 + 推論）
- 全件処理時間: 約 60 分

実証の制約:

- 本検証マシンは `ANTHROPIC_API_KEY` を持たないため、**legacy 経路（直接 API 経路）の同条件実行は不可能**
- 代わりに 2 経路のソースコード差分を理論分析し、判定ブレを生む構造的要因を `.logs/KMD-154/diff-analysis.md` に記録した
- 完全な対照実験（両経路で同じ violation 集合になるか）は ANTHROPIC_API_KEY を持つ環境での後続検証に委ねる（KMD-154 follow-up）

**理論的差分要因（コードレビューで特定）**:

| 観点 | legacy 経路 | subagent 経路 | リスク |
|---|---|---|---|
| セクション抽出 | 固定 python ロジック (`run_legacy()` 内 `py_extract`) | エージェント定義 prompt で「同等の python ロジックを再利用」と指示 | エージェントの解釈次第でセクション境界がブレる |
| 入力 hash 計算式 | shell 側で `sha256("<rel_path>\|H<level>\|<title>\|<body>")` | エージェント定義 prompt 内に式を記述、実装は agent 側 | 入力前後空白・改行コードの正規化差がヒット率を下げる |
| Cache 構造 | `{"section_context": {hash: verdict}, "version": 1}` 仕様 | 同一仕様を prompt で指示 | 仕様一致だが実装責任が agent 側にあり再現性は弱い |
| 推論コンテキスト | 記事全文 + 質問セクションのみ（API 直叩き） | エージェント定義 + Read 取得記事 + Claude Code の dynamic system prompt（cwd / env / memory 等） | dynamic system prompt が判定再現性に影響しうる |
| 出力境界 | API レスポンス 1 つ = `YES` または `NO: <理由>` | エージェントが NDJSON を組み立てる複合タスク | 組み立て中に判定が変化する可能性 |

**運用上の判断**:

- KMD-152 で「最小権限の allowlist 化」を入れた際、`claude -p --allowedTools <tools...> "$prompt"` の引数順序が `--allowedTools` の variadic option に prompt まで貪欲に取られる Commander.js の挙動に踏まれていた。これは KMD-150 → KMD-152 の流れの中で **CI / 統合テストが無いため検出できなかった**バグであり、subagent 経路は 5 月初頭以降ずっと壊れていた。KMD-154 のスモーク実行で初めて顕在化
- 修正は 1 行（`printf '%s' "$prompt" | claude -p ...` で stdin に逃がす）。今後 `--allowedTools` を含む CLI 呼び出しを書く際は **可変長オプションの後に位置引数を置かない / stdin で受け渡す** を規約化する
- subagent 経路の cache file は 1 セッション内で正しく書き込まれることを確認済み（25 entries / 12 件の article 完走時点）

**section-context-missing 0 件の解釈**:

- すべての article が H2/H3 セクション単独で文脈を成すよう書かれている、と Haiku が判定した
- ただし Haiku の判断ブレ幅は単独試行では計測できないため、`--exclude-dynamic-system-prompt-sections` 利用や複数試行の median を取るなどの安定化は別チケット（後続検証）で扱う
- 2 経路の絶対一致（一致率 100%）は理論上保証されていないが、本 wiki の現在の文体では両経路とも違反 0 が想定される（差分検証の必要性が下がる方向）

### 2. Phase 移行のトリガー

| Phase | 状態 | トリガー |
|---|---|---|
| Phase 1（現行） | wiki 全件を Prompt Caching でプロンプトに投入 | デフォルト |
| Phase 2 | カテゴリ単位（architecture / decisions / practices 等）で分割投入 | wiki 総量が **15 万トークン**を超え、cache miss 時のコスト・レイテンシが許容外になったとき |
| Phase 3 | embedding ベース検索層 + 必要記事のみ投入 | wiki 総量が **20 万トークン**を超えたとき（Anthropic Claude のコンテキスト上限・キャッシュ単価の観点） |
| Phase 4 | 検索層 + 要約レイヤ + ホット記事の事前ロード | Phase 3 でも応答品質が劣化したとき |

`scripts/wiki/load_all.sh` は出力末尾に `# Total: ~XXkB / ~XX,XXX tokens` を stderr に出すので、定期的に総量を観測し、15 万 / 20 万トークン到達前に Phase 移行を検討する。

### 3. モデル割り当て方針（Opus / Sonnet / Haiku）

| 分類 | モデル | 基準 |
|---|---|---|
| Orchestrator（メイン） | **Opus** | `~/.claude/settings.json` で設定 |
| 判断・創造・分析系 subagent | **Opus** | 設計判断・コードレビュー・PRD 作成・振り返り分析・リサーチなど、深い推論が必要なタスク |
| 機械的操作系 subagent | **Sonnet** | ビルド実行・マージ操作・定型的なコメント修正など、手順が明確で判断余地の少ないタスク |
| 大量バッチ系 subagent / scripts | **Haiku** | 短い構造化タスクをバッチで大量に回す用途。下記の「Haiku の用途」を参照 |

### 4. Haiku の用途

Haiku は **短い構造化タスクをバッチで大量に回す**用途に使う。1 件あたりの推論深度は浅くてよいが、件数が多くスループットとコストが効くケースに適する。

代表的な用途:

- **チャンク contextual prefix 生成**: wiki / コードチャンクの先頭に「このチャンクは何の文脈に属するか」を 1〜2 文で付与する処理
- **セクション単独文脈の YES/NO 判定**: 「このセクションは外部知識なしで読めるか？」のような二値判定
- **unlinked mentions の文脈一致判定**: wiki 内で `[[wikilink]]` 化されていない言及を検出し、リンク先候補との一致を判定
- **評価クエリの半自動生成**: テスト・評価セット用のクエリ候補を記事から自動抽出

**Haiku 利用時の必須ルール**:

1. **Claude Code subagent 経由で起動する（KMD-150 以降の必須）**: `ANTHROPIC_API_KEY` を直接利用するのではなく、`.claude/agents/<name>.md`（`model: haiku`）として subagent を定義し、`claude -p --agent <name>` で呼ぶ。API キーの発行・配布が不要になる
2. **Prompt Caching を必ず併用**: `cache_control: { type: "ephemeral" }` を文書部分（system or user の static block）に付与する。Haiku は単価が安いとはいえ、cache miss を量産するとコストが逆転する。subagent 経由の場合は Claude Code 側のキャッシュ機構が同等の役割を担う
3. **バッチ処理を優先**: 1 記事内の複数チャンクは 1 セッションで連続処理する。`scripts/wiki/ask.sh` のような共通ヘルパーから呼び、セッション単位のキャッシュを活かす
4. **失敗時のフォールバック**: リトライ 3 回、最終失敗は元入力をそのまま通過させて警告を stderr に出す（処理を止めない）。Haiku は判断が浅いぶん偶発的な誤りが起こりやすいので、品質ゲートとして「失敗時は no-op に倒す」を徹底する
5. **content_hash ベースの差分処理**: 入力チャンクの内容ハッシュを記録し、変更のないチャンクは再生成しない。記事追加 / 更新のたびに全件を再処理しない

具体的な Haiku 利用箇所は KB2 〜 KB4 系チケットで個別の subagent / scripts に展開する:

- KB2-2 / KB2-3: チャンク contextual prefix 生成
- KB3-2 / KB3-4: セクション単独文脈判定 / unlinked mentions 判定（KMD-150 で subagent 経由化）
- KB4-2: 評価クエリの半自動生成

実装済みの subagent:

- `kobaamd_lint_section_context` (`.claude/agents/kobaamd_lint_section_context.md`) — `scripts/wiki/lint.sh` のルール 4 (section-context-missing) を担当。`scripts/wiki/lib/section-context-check.sh` から `claude -p --agent` 経由で起動される

### 5. フォールバック手順（ヘルパー未整備時 / ad-hoc 用途）

KMD-46 / KMD-47 のヘルパーが未整備の段階、もしくは手元で素早く試したいときは以下の手順を取る。**ただし subagent の自動処理ではこの経路を使わず、必ずヘルパー経由にする**。

1. `docs/wiki/index.md` から関連記事を絞り込む
2. 関連記事を Read で読み込み、subagent プロンプトに埋め込んで合成回答する
3. 結果に有用な分析が含まれていれば、新規記事として wiki に追加する

### 6. SCHEMA.md / CLAUDE.md との関係

本記事は KMD-49（[KB1] CLAUDE.md / SCHEMA.md に運用方針を明記）の AC を公開可能領域で表現したもの。次の参照関係を持つ。

- `docs/wiki/SCHEMA.md` の「ワークフロー > Query」節に Phase 1 標準手順と Phase 移行トリガーを記載
- `CLAUDE.md`（リポジトリでは gitignore 管理）の「自律開発パイプライン > Wiki 参照ポリシー」と「モデル割り当て方針 > Haiku の用途」に同等の運用ガイドを記載
- subagent 開発者は本記事 + SCHEMA.md を参照すれば、CLAUDE.md にアクセスできない環境でも標準運用を再現できる

## Related

- [[postmortem-patterns]]
- [[prd-quality-cycle]]

## Sources

- `docs/wiki/SCHEMA.md`
- KMD-45（[KB1] LLM-Wiki を prompt-cache 利用レベルまで引き上げる）
- KMD-46（[KB1] wiki 全件連結スクリプト scripts/wiki/load_all.sh の実装）
- KMD-47（[KB1] subagent から wiki 全件参照を行うヘルパーの整備）
- KMD-48（[KB1] Prompt Caching のコスト・レイテンシ計測ベンチマーク）
- KMD-49（[KB1] CLAUDE.md / SCHEMA.md に運用方針を明記）
- KMD-150（[KB2] section-context-missing lint を Claude Code subagent (Haiku) 経由に置換）
- KMD-152（[KB2-followup] section-context-check の subagent を最小権限 allowlist 化）
- KMD-154（[KB2-followup] 2 経路の判定差分検証 + subagent 経路の CLI 引数バグ修正）
