---
title: Wiki 参照ポリシー（Prompt Caching 標準運用）
category: practices
tags: [wiki, prompt-caching, anthropic, haiku, sonnet, opus, knowledge-base]
sources: [docs/wiki/SCHEMA.md, KMD-45, KMD-46, KMD-47, KMD-48, KMD-49]
created: 2026-05-04
updated: 2026-05-04
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

1. **Prompt Caching を必ず併用**: `cache_control: { type: "ephemeral" }` を文書部分（system or user の static block）に付与する。Haiku は単価が安いとはいえ、cache miss を量産するとコストが逆転する
2. **バッチ処理を優先**: 1 記事内の複数チャンクは 1 セッションで連続処理する。`scripts/wiki/ask.sh` のような共通ヘルパーから呼び、セッション単位のキャッシュを活かす
3. **失敗時のフォールバック**: リトライ 3 回、最終失敗は元入力をそのまま通過させて警告を stderr に出す（処理を止めない）。Haiku は判断が浅いぶん偶発的な誤りが起こりやすいので、品質ゲートとして「失敗時は no-op に倒す」を徹底する
4. **content_hash ベースの差分処理**: 入力チャンクの内容ハッシュを記録し、変更のないチャンクは再生成しない。記事追加 / 更新のたびに全件を再処理しない

具体的な Haiku 利用箇所は KB2 〜 KB4 系チケットで個別の subagent / scripts に展開する:

- KB2-2 / KB2-3: チャンク contextual prefix 生成
- KB3-2 / KB3-4: セクション単独文脈判定 / unlinked mentions 判定
- KB4-2: 評価クエリの半自動生成

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

- [[ポストモーテムから学ぶ実装パターン]]
- [[PRD 品質サイクル]]

## Sources

- `docs/wiki/SCHEMA.md`
- KMD-45（[KB1] LLM-Wiki を prompt-cache 利用レベルまで引き上げる）
- KMD-46（[KB1] wiki 全件連結スクリプト scripts/wiki/load_all.sh の実装）
- KMD-47（[KB1] subagent から wiki 全件参照を行うヘルパーの整備）
- KMD-48（[KB1] Prompt Caching のコスト・レイテンシ計測ベンチマーク）
- KMD-49（[KB1] CLAUDE.md / SCHEMA.md に運用方針を明記）
