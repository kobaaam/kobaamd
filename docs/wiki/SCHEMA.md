# LLM Wiki Schema

kobaamd の設計思考・意思決定プロセス・技術知見を蓄積する知識ベース。
Karpathy の LLM Wiki パターン（RAG 代替の知識コンパイル設計）に基づく。

## ディレクトリ構造

```
docs/wiki/
├── SCHEMA.md          ← 本ファイル（構造規則・ワークフロー定義）
├── index.md           ← 全記事カタログ（カテゴリ別、1行説明付き）
├── log.md             ← 操作履歴（追記専用、時系列）
├── raw/               ← 生ソース（不変、LLM は読むだけ）
│   ├── postmortem/    ← docs/learnings/ へのシンボリックリンク or コピー
│   ├── adr/           ← docs/adr/ へのシンボリックリンク or コピー
│   └── external/      ← 外部記事・論文のスナップショット
└── articles/          ← LLM が生成・更新する wiki 記事
    ├── architecture/  ← アーキテクチャ（WKWebView 戦略、メモリ管理等）
    ├── concepts/      ← 概念・パターン（MVVM, Observable, etc.）
    ├── decisions/     ← 意思決定の文脈と理由（ADR の統合ビュー）
    ├── components/    ← コンポーネント知識（EditorView, AIService, etc.）
    └── practices/     ← 開発プラクティス（パイプライン運用、レビュー基準等）
```

## 記事フォーマット

```markdown
---
title: 記事タイトル
category: architecture | concepts | decisions | components | practices
tags: [tag1, tag2]
sources: [raw/adr/0001.md, raw/postmortem/KMD-4.md]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# タイトル

## Summary
1-3行の要約。

## Content
本文。関連記事への [[wikilink]] を含む。

## Related
- [[関連記事1]]
- [[関連記事2]]

## Sources
- 参照した raw ソース一覧
```

## 記載規約

LLM が wiki を読み込む際の文脈圧縮（Anthropic Prompt Caching / 将来の Contextual Retrieval）を効きやすくするため、記事の書き方は以下の規約に従う。

`kobaamd_update_wiki` をはじめとする wiki 編集系 subagent は、**記事を更新・新規作成する際に必ず本セクションの規約を満たすこと**。違反する記事を生成しない。

### 1. セクション単独可読性（H2 / H3）

各 H2 / H3 セクションは、それ単体で「何の話か」が伝わるように書く。具体的には、

- セクション冒頭の 1〜2 文で、対象（プロジェクト名・コンポーネント名・概念名など）を明示する
- 「これ」「上記」「先ほど述べた」のような前方参照だけで主語を済ませない
- 親セクションを読まないと意味が取れない見出し名（例: `## 詳細`、`## 補足`）を避ける

**違反例**:

```markdown
## 仕組み

これは AppKit の NSTextView を SwiftUI でラップして実装している。
上記の理由でフォーカス管理が難しい。
```

**適合例**:

```markdown
## EditorView の仕組み

kobaamd の EditorView は、AppKit の NSTextView を SwiftUI で
NSViewRepresentable としてラップして実装している。
SwiftUI と AppKit のフォーカス管理の整合が必要なため、
firstResponder の移譲ロジックを ViewModel 側に集約している。
```

### 2. `<!-- llm-context: ... -->` による文脈補足

セクションタイトルだけでは前提が不足し、本文を 1 段落以上膨らませると冗長になる場合は、セクション直下に HTML コメントで 50〜100 文字の文脈説明を入れる。これは人間の読者には不可視で、LLM がチャンク単位で読むときに「このチャンクは何の話か」を即座に掴むためのメタ情報として機能する。

- 形式: `<!-- llm-context: <50〜100 文字> -->`
- 50 文字未満は情報量不足、100 文字超は本文に書くべき
- 1 セクションにつき最大 1 個。複数置かない
- 必ずしも全セクションに付ける必要はない。**セクション名だけで十分文脈が伝わる場合は不要**

**違反例**（セクション名だけでは何の話か曖昧、かつ文脈補足もない）:

```markdown
## 設定

DEFAULT_TIMEOUT は 30 秒、MAX_RETRIES は 3。
```

**適合例**:

```markdown
## AIService のリトライ設定
<!-- llm-context: kobaamd の AIService が外部 LLM API を呼ぶときのタイムアウトとリトライ回数。失敗時挙動の設計判断。 -->

DEFAULT_TIMEOUT は 30 秒、MAX_RETRIES は 3 回。
タイムアウト時は指数バックオフでリトライする。
```

### 3. frontmatter 必須フィールドの整合ルール

すべての `articles/**/*.md` は以下の frontmatter フィールドを **必ず** 持つ。欠落・空値は不可。

| フィールド | 型 | 規則 |
|---|---|---|
| `title` | string | 記事の H1 と完全一致させる |
| `category` | enum | `architecture` / `concepts` / `decisions` / `components` / `practices` のいずれか 1 つ。ファイルパス `articles/<category>/...` と一致させる |
| `tags` | string[] | 1 個以上。命名規約は本セクション「4. タグ命名規約」を参照 |
| `sources` | string[] | 0 個でも可（外部 source なしで完結する記事もある）。リポジトリルートからの相対パスで記述（例: `docs/learnings/2026-05-04-KMD-107.md`） |
| `created` | date | ISO 8601（`YYYY-MM-DD`）。記事新規作成時の日付。**以後変更しない** |
| `updated` | date | ISO 8601（`YYYY-MM-DD`）。記事を更新するたびに今日の日付に書き換える |

`updated` は `created` と同日 or それ以降。`updated < created` は不正。

**違反例**:

```yaml
---
title: EditorView の仕組み
category: editor       # ← 不正カテゴリ
tags: []               # ← 空配列は不可
created: 2026-05-01
# updated 欠落
---

# EditorViewの仕組み      ← title と表記揺れ（半角スペース有無）
```

**適合例**:

```yaml
---
title: EditorView の仕組み
category: components
tags: [editor, nstextview, swiftui-appkit-bridge]
sources:
  - docs/learnings/2026-05-04-KMD-107.md
created: 2026-05-01
updated: 2026-05-04
---

# EditorView の仕組み
```

### 4. タグ命名規約（lowercase-kebab）

`tags` の各要素は以下の規約に従う。

- 全文字 lowercase
- 単語区切りは `-`（ハイフン）
- アンダースコア（`_`）・空白・大文字・キャメルケース・スネークケース禁止
- 1 タグの長さは 30 文字以下
- 略語（`api`, `ui`, `pr`）は小文字のまま使う（`API` 不可）

**違反例**:

```yaml
tags: [SwiftUI, NSTextView, Prompt_Caching, "swift code", PRReview]
```

**適合例**:

```yaml
tags: [swiftui, nstextview, prompt-caching, swift-code, pr-review]
```

### 5. Related セクションの双方向性

`## Related` で `[[wikilink]]` を使って他記事を参照する場合、**参照先の記事も自記事を Related に書く**こと（双方向リンク）。一方向リンクは禁止。

これにより、LLM がどちらの記事から入っても関連記事へ到達でき、孤立記事の検出も容易になる。

新規記事を追加した時 / 既存記事の Related に追記した時は、必ず参照先の Related も同時に更新する。

**違反例**（A だけが B を参照、B は A を参照していない）:

```markdown
<!-- articles/components/editor-view.md -->
## Related
- [[ai-service-retry]]

<!-- articles/components/ai-service.md -->
## Related
（editor-view への参照なし）
```

**適合例**:

```markdown
<!-- articles/components/editor-view.md -->
## Related
- [[ai-service-retry]]

<!-- articles/components/ai-service.md -->
## Related
- [[editor-view]]
```

### 6. wikilink の解決ルール

`[[name]]` 形式の wikilink は、以下の優先順位で解決する。

1. **slug 一致を最優先**: `articles/**/<name>.md`（ファイル名から拡張子を除いたもの = slug）に完全一致する記事があれば、その記事を参照先とする
2. **`frontmatter.title` 一致（フォールバック）**: slug で見つからない場合、各記事の frontmatter `title` が `name` と完全一致する記事を参照先とする
3. どちらにも一致しない場合は **broken-link** として `kobaamd_lint_wiki`（rule: `broken-link`）が検出する
4. 同一 `name` に対して slug 一致と title 一致が両方成立する場合は **slug を優先**する

#### 新規生成・更新時の規則（重要）

`kobaamd_update_wiki` をはじめとする wiki 編集系 subagent は、新規 wikilink を生成・追記するとき **必ず slug 形式（lowercase-kebab）を使う**。`frontmatter.title` 形式（日本語タイトル等）での新規生成は禁止。

理由:

- title はリネームや表記揺れ（半角スペース有無、約物の差異）の影響を受けやすく、broken-link を増やす要因になる
- slug はファイル名と一意に対応するため、リファクタ耐性が高い
- title 揺れが起きても lint で検出できるよう、生成は slug に固定して入口を絞る

既存の wiki に存在する `frontmatter.title` 形式の wikilink（例: `[[エディタコア (NSTextViewWrapper)]]`、`[[AppKit-SwiftUI ブリッジ]]` など）は、移行コスト・既存資産温存の観点で **温存**する。lint はこれらを broken-link 判定しない（上記ルール 2 のフォールバック解決により有効リンクとして扱う）。

#### 違反例 / 適合例

**違反例**（新規生成で title alias 形式を使う、SCHEMA 違反）:

```markdown
<!-- 新規追記する Related に title 形式を使うのは禁止 -->
## Related
- [[エディタコア (NSTextViewWrapper)]]   ← 新規生成では NG
```

**適合例**（新規生成は slug 形式に固定）:

```markdown
## Related
- [[editor-core]]   ← slug 形式 OK
```

ただし**既に書かれている `[[エディタコア (NSTextViewWrapper)]]` を slug 形式に置き換える義務はない**。ルール 2 のフォールバックで解決される。

## ワークフロー

### Ingest（取り込み）
1. raw/ にソースを追加（postmortem、ADR、外部記事など）
2. LLM がソースを読み、キーポイントを抽出
3. 既存記事の更新 or 新規記事の作成
4. 関連記事の [[wikilink]] を更新
5. index.md を更新
6. log.md に操作を記録

### Query（照会）

kobaamd では **wiki 全件を Anthropic Prompt Caching でプロンプトに投入する方式** を Phase 1 標準運用とする（`CLAUDE.md` の「Wiki 参照ポリシー」を参照）。検索層（embedding / BM25）は wiki 総量が 20 万トークンを超えるまで導入しない。

**標準手順（Phase 1: Prompt Caching）**:

1. `scripts/wiki/load_all.sh` で `docs/wiki/articles/**/*.md` を frontmatter 付きで連結し、1 つの static block を作る（KMD-46 で整備）
2. `scripts/wiki/ask.sh "<query>"` で wiki 全件 + クエリを Claude API に投げる（KMD-47 で整備）。文書部分には `cache_control: { type: "ephemeral" }` を付与し、5 分以内の再呼び出しで Cache Hit にする
3. 応答を取得し、必要なら有用な分析を新規記事として wiki に追加する
4. 実行ログから Cache Hit / Miss を確認し、cache miss が多い場合は呼び出し間隔の見直しを行う

**フォールバック手順（ヘルパー未整備時 / ad-hoc 用途）**:

1. `index.md` から関連記事を絞り込む
2. 関連記事を Read で読み込み、subagent プロンプトに埋め込んで合成回答する
3. この経路は **手動 ad-hoc 用**であり、subagent の自動処理では使わない（ヘルパー経由を必須とする）

**Phase 移行のトリガー**:

- wiki 総量 **15 万トークン** 超過: Phase 2（カテゴリ単位投入）へ移行検討
- wiki 総量 **20 万トークン** 超過: Phase 3（embedding ベース検索層 + 必要記事のみ投入）へ移行
- wiki 総量は `scripts/wiki/load_all.sh` の出力末尾サマリ（`# Total: ~XXkB / ~XX,XXX tokens` を stderr 出力）で観測する

### Lint（メンテナンス）
1. 矛盾する記述の検出
2. 孤立記事（どこからもリンクされていない）の特定
3. 古くなった情報のフラグ付け

## パイプライン統合

- `pipeline_weekly` に wiki ingest ステップを追加予定
- `review_postmortem` 完了時に自動で wiki を更新
- ADR 作成時に自動で decisions/ に記事を生成
