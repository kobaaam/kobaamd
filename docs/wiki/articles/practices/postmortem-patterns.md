---
title: ポストモーテムから学ぶ実装パターン
category: practices
tags: [postmortem, patterns, codex, testing, observability, auto-carve-out, carve-out, clean-approve]
sources:
  - docs/learnings/2026-04-28-KMD-4.md
  - docs/learnings/2026-04-28-KMD-6.md
  - docs/learnings/2026-04-29-KMD-20.md
  - docs/learnings/2026-04-28-KMD-22.md
  - docs/learnings/2026-05-05-KMD-54.md
  - docs/learnings/2026-05-06-KMD-144.md
  - docs/learnings/2026-05-08-KMD-120.md
  - docs/learnings/2026-05-08-KMD-153.md
  - docs/learnings/2026-05-15-KMD-186.md
created: 2026-04-30
updated: 2026-05-15
---

# ポストモーテムから学ぶ実装パターン

## Summary

KMD-4/6/20/22/120/144/153 の振り返りから抽出した再発防止パターン集。実装プロンプトへの反映事項を体系化。

## Content

### パターン 1: 影響範囲マップ必須化

**問題**: PRD に「変更してはいけないファイル」が未記載 → Codex がスコープ外を変更
**対策**: PRD セクション 8 に「変更禁止ファイル一覧」を必須化
**効果**: KMD-20 でリワーク 0 回を達成

### パターン 2: View → Service 直呼び禁止

**問題**: `TemplatePickerView` が `FileService()` を直接インスタンス化（MVVM 違反）
**対策**: 実装プロンプトに「View から Service を直接呼ばず ViewModel 経由」を明記
**根拠**: 既存コードの慣習（SettingsView）が新規ファイルに伝播した

### パターン 3: onAppear の非同期化デフォルト

**問題**: `onAppear` 内のファイル I/O がメインスレッドをブロック
**対策**: ファイル I/O は必ず `Task { await ... }` パターンを使用

### パターン 4: テストは実装対象を経由

**問題**: テスト名が `ensureCustomTemplateDirectory` だが、実際は FileManager を直呼びしており FileService を一切検証していなかった
**対策**: テスト名に登場するメソッドは必ずテスト内で呼び出す

### パターン 5: ID 衝突を前提にした設計

**問題**: `DocumentTemplate.id` がファイル名のみ → ビルトインとカスタムで衝突可能
**対策**: `Identifiable.id` は名前空間プレフィックス付き（例: `"builtin:"`, `"custom:"`）

### パターン 6: concern の重大度分類

**問題**: KMD-22 で concern 6件が全て同列に並び、重要度が不明
**対策**: concern を severity (high/medium/low) で分類し、high は REQUEST_CHANGES 相当に

### パターン 7: クリーン APPROVE 直行の 4 条件
<!-- llm-context: KMD-54 で実証された、Human in Review を経由せず Reviewed 直行できる PR の必要十分条件。AI レビュー観点が独立評価可能になる組み合わせ。 -->

**問題**: AI レビューが `concern>0` または `[BREAKING]` を理由に Human in Review に滞留すると、リードタイムが伸び自律パイプラインのスループットが落ちる
**対策**: 以下 4 条件を PRD・実装の両段階で揃えると、`kobaamd_review_pr` がクリーン APPROVE → Reviewed 直行できる:

1. **PRD AC が網羅的**（観察可能で 3 件以上、抽象表現なし）
2. **影響範囲マップ通りの変更**（PRD section 8 に列挙したファイルのみ。マップ外への手出しなし）
3. **wiki-derived patterns を implement 側が自発適用**（quoting / `set -euo pipefail` / `trap` / 入力バリデーション。`security-hardening.md` 由来）
4. **auto-carveable concern は別チケット化**（テスト整備・observability 強化など独立改善は本 PR を block しない）

**実例**: KMD-54（pipeline_weekly に lint_wiki 組み込み）は 4 条件すべて充足し、Todo → Done が約 17 分・リワーク 0 回で完了した。

### パターン 8: auto carve-out には re-open 手順をコメントに明記する
<!-- llm-context: kobaamd_review_pr が auto-carveable concern を別チケットに退避する際、人間が「本 PR で対応すべき」と判断したときのリカバリ経路を carve-out 先 issue 本文に必ず書き込む規約。 -->

**問題**: AI が独立改善として別チケットに carve-out した concern が、運用上は「AI による責務逃れ」に見える / 取り消し手順が不明で人間が介入しづらい
**対策**: carve-out 先 issue 本文に以下 2 行を必ず含める:

- `親チケット: KMD-XX (auto-carved-out by kobaamd_review_pr)`
- `補足: 人間が「本 PR で対応すべき」と判断した場合は本チケットを revert/close して、KMD-XX を re-open してください`

**根拠**: KMD-54 では本規約を満たす形で KMD-141（テスト整備）/ KMD-142（投稿失敗 observability）が起票され、carve-out のリカバリ経路が運用上担保された。`kobaamd_review_pr` のプロンプトに本規約を明文化することで、carve-out の信頼性が AI レビュー全体で底上げされる。

### パターン 9: 依存逆順ガードを PRD と実装の両方に書く
<!-- llm-context: 依存先 PR が未マージのまま依存元 PR がマージされても、weekly / daily ジョブが落ちないようにするためのガードパターンと、それを PRD section 8 で先に明文化する運用。 -->

**問題**: `kobaamd_assign_work` は parent / blocked-by を見ないため、依存元 PR が依存先 PR より先にマージされうる
**対策**: 依存先 script の不在時に warning + skip + exit=0 で抜けるガードを、**PRD section 8「その他リスク」と実装の両方に書く**。レビュー側もこれを独立観点として pass 判定する。

**実例**: KMD-54 では `lint.sh`（依存先 KMD-52）が未マージでも weekly が落ちないガードを実装に組み込んだ。実際 PR #63（依存元）が PR #62（依存先）より先にマージされたが、main 上で安全に動作した。

詳細パターンは [[dependency-inversion-guard]] を参照。

### パターン 12: サイレント失敗予防機構の自己観測責務
<!-- llm-context: KMD-144 ingest_history.sh で導入した「lint silent skipped を観測する機構」自身がサイレント失敗するリスクと、観測機構を新規追加するときの設計責務についてのパターン。 -->

**問題**: `kobaamd_update_wiki` の lint ゲート silent skipped を検出する `scripts/wiki/ingest_history.sh check` を新規追加したが、機構自身が以下 3 重で silent fail し得た。

1. `set -u` + `trap cleanup EXIT` + `local var=""` の組み合わせで、cleanup 発火時に `comment_file: unbound variable` で死ぬ
2. 死んだ exit 1 を呼び出し側 `kobaamd_update_wiki` step 6.f が `|| true` でマスクする
3. マスクされた結果 `HISTORY_REPORT=""` となり、`grep -E '^warning='` が空一致して warning 検出機能ごと無声化する

これは [[security-hardening]] の「サイレント失敗パターン」表の「検証ロジックが always-pass」と同型の構造。**サイレント失敗を予防する機構を新規追加するときは、機構自身が同じパターンで死なないことを AC に含める**。

**対策**:

- 観測機構の出力には必須スキーマ（例: `warning=` 行が常に含まれること）を定義し、呼び出し側で assert する
- `|| true` で握り潰す前に、最低限「実行されたか」「期待行が出力に含まれるか」を確認する
- 観測機構そのもののテストに「依存コマンド失敗 / 環境変数未設定 / 不正入力」のリカバリ系シナリオを最低 1 つ含める

**出所**: KMD-144 review_pr concern (auto-carveable → KMD-146 に集約)

### パターン 13: 親 PR の auto-carveable concern を統合チケットとして起票する
<!-- llm-context: KMD-55 (PR #65) のレビューで残った 2 件の改善を、別個の小チケットではなく 1 つの統合チケット (KMD-144) として起票したケースの判断条件。 -->

**問題**: 親 PR のレビューで auto-carveable な concern が複数残ったとき、1 件 1 チケットに分割すると個々が小さすぎて優先度が上がらない。Backlog に放置されやすい。

**対策**: 以下 3 条件が揃う場合、複数の auto-carveable concern を 1 つの統合チケットとして起票してよい。

1. **同じファイル群に閉じる**（例: KMD-144 はいずれも `kobaamd_update_wiki` 周辺）
2. **影響範囲が共通**（同じモジュール / 同じパイプラインステップ）
3. **同じレビュー観点で評価できる**（例: 「ingest プロセスの可観測性」というドメインでまとまる）

逆にこの 3 条件が揃わないなら、無理に統合せず個別起票にする（PR が肥大化して影響範囲レビューが難しくなる）。

**効果**: KMD-144 では 2 件の改善を 1 PR で処理し、レビューは Reviewed 直行で 9 分（in Review → Reviewed → Done）の高速サイクルを実現した。

**出所**: KMD-55 (PR #65) review → KMD-144 (PR #70) のサイクル

### パターン 14: APPROVE auto carve-out が成立する 3 条件
<!-- llm-context: kobaamd_review_pr が「APPROVE / Reviewed 直行 / Human in Review を経由しない」と判定するための具体条件。実装フェーズで意識すると Reviewed 直行を狙いやすい。 -->

**問題**: `kobaamd_review_pr` が `Human in Review` 経由ではなく `Reviewed` 直行で判定する条件が暗黙化されており、実装側でどこまで意識すれば auto carve-out で通るかが不明だった。

**対策**: 以下 3 条件をすべて満たすと、review_pr は APPROVE auto carve-out で `Reviewed` 直行を選択する。

1. **PRD AC を完全充足**（全項目 pass）
2. **影響範囲が PRD 記載と一致**（PR コメントで「触れていない箇所」を明示）
3. **残 concern が `auto-carveable` 分類のみ**（rework=0, human-judgment=0, `[BREAKING]` なし）

逆に、PRD AC 充足が pass でも、影響範囲が PRD と乖離している、または concern が「仕様判断必要」に該当すると `Human in Review` に入る。実装段階で「PRD に書かれた影響範囲だけを触る」「CSI 改善は別 issue 起票で残す」を意識すると Reviewed 直行率が上がる。

**効果**: KMD-144 ではこの 3 条件を満たして `Reviewed` 直行 → 自動マージで完了した。リードタイムは同日内、リワーク 0 回。

**出所**: KMD-144 (PR #70) review_pr 判定経路

### パターン 15: AC は「観測 → 文言」の順で書く
<!-- llm-context: PRD AC で「対象ファイルから X を削除」のような実測前提項目を書く前に、必ず grep で実在件数を確認してから AC を確定する規約。KMD-120 で「5 ファイル中 2 ファイルしか該当しない」と実装段階で判明したケースの再発防止。 -->

**問題**: KMD-120 の PRD AC は「5 subagent から `Read CLAUDE.md` 行を削除」と仮説前提で書かれていたが、実装段階で grep すると該当行が実在したのは 2 ファイルのみ（残り 3 は元々 no-op）と判明した。実装側は「2/5 のみ該当・残り 3 は session-context 前提の文言追加 + Constraints 補強で対応」と PR / Linear に透明開示するコメントを残す追加コストが発生した。

**対策**: PRD 作成時、AC で「対象ファイル群から X を削除 / 変更」のような実測前提の項目を書く前に、`grep -rn 'pattern' <files>` で実在件数を確認し、AC に **件数または「該当箇所のみ」** を明記する。`kobaamd_create_prd` の Workflow に「AC 中に実測前提項目があれば、PRD 確定前に grep で対象ファイル群への該当件数を確認する」ステップを追加することで再発防止できる。

**出所**: KMD-120 (PR #76)

### パターン 16: subagent MD 編集時の frontmatter 整合チェック
<!-- llm-context: .claude/agents/*.md は frontmatter（description / tools / model）と本文（Workflow / Constraints / Final Report Format）の二重構造。本文だけ更新して frontmatter が取り残されると lint で検出されにくく auto-carve に頼ることになる。 -->

**問題**: KMD-120 で 5 subagent ファイルの本文（Workflow / Constraints）を更新したが、frontmatter `description:` フィールドの整合まで行き届かず、auto-carve（KMD-156）対象になった。subagent ファイルの構造に対する「変更時の整合性チェックリスト」が implement_code プロンプトに無いため、本文更新時に frontmatter が取り残されやすい。

**対策**: `kobaamd_implement_code` の Constraints / Workflow に「subagent 定義 MD（`.claude/agents/*.md`）を変更する場合、frontmatter `description:` フィールドと本文の整合をセットでチェックすること」を追記。auto-carve に頼らないチェックリスト化。詳細は [[subagent-prompt-design]] §4 を参照。

**出所**: KMD-120 (PR #76) → KMD-156 (auto-carved-out)

### パターン 17: 観測前提の AC は観測手段もセットで設計する
<!-- llm-context: 「次回 postmortem で X を確認」のような観測前提 AC は、観測手段（集計スクリプト・ログ抽出方法）が未整備だと検証不能になる。観測手段の整備を同 PR か別チケットでセットにする運用。 -->

**問題**: KMD-120 PRD AC 4 項目目「次回 postmortem で Karpathy Guidelines / 命名規則違反が発生していないことを確認」「input token 数の削減を観測」は観測前提だが、launchd ログから input token を集計するスクリプトは未整備。本 postmortem 時点でも定量検証ができていない（~480k tokens/日 削減は推算止まり）。

**対策**: 観測前提の AC を含む PRD は、観測手段（集計スクリプト・ログ抽出方法）の整備を **同 PR の影響範囲または別チケット** として明記する。`kobaamd_research_create_ticket` / `kobaamd_create_prd` のプロンプトに「観測前提 AC を検出した場合、観測手段の起票も併せて提案」を追加。観測手段が未整備なら AC 自体を「次回 postmortem で観測する（観測手段は KMD-XX で整備）」と書き換える運用に倒す。

**出所**: KMD-120 (PR #76)

### パターン 18: 観測機構の変更には観測機構自体の smoke test を初手で含める
<!-- llm-context: section-context-check.sh のような観測 / 中継機構を変更する PR では、変更同 PR で smoke test まで一緒に書くのが筋。後工程の auto-carve に倒すと CI で回らないままマージされる。 -->

**問題**: KMD-153（`scripts/wiki/lib/section-context-check.sh` の `run_subagent()` で stdout/stderr を分離して agent の WARN を呼び出し元 stderr に中継する 17 行追加 / 2 行変更）では、smoke test を「mock claude を使った成功 / 失敗パスの手動検証」だけで済ませ、自動 smoke test は KMD-171 として auto-carve した。観測機構の変更にしては test 戦略が PRD AC の段階で言語化されていなかったため、初手で test を含めた PR を出す選択肢が消えていた。

**対策**: 観測機構（stderr / log / metric の中継・出力フォーマット変更を含む shell script や subagent ヘルパー）を変更する PR は、**変更と同じ PR で shell smoke test まで書く**のを標準とする。観測機構の変更は通常少行数（数十行）で済むため、smoke test を同梱しても PR 規模が破綻しない。`kobaamd_review_pr` のプロンプトに「観測機構変更（stderr / log / metric の中継）を検出したら、smoke test の有無を concern に上げる」観点を追加し、test を欠く場合は rework か auto-carve かを既存ロジックで分類させる。

PRD 側にも反映する: `docs/prd/` テンプレートに「テスト戦略」セクションを **AC とは別枠で** 設け、自動テスト / 手動検証 / smoke test の方針を 1 行書かせる。観測機構変更系 PRD では「観測機構自体の回帰検出 smoke test を本 PR で書く」を必ず含める。

**出所**: KMD-153 (PR #84) → KMD-171 に smoke test 自動化が auto-carve

### パターン 19: review_security はゲート観点を PR の本質に応じて選ぶ
<!-- llm-context: kobaamd_review_security が postmortem-patterns §12「観測機構の自己観測責務」のような重い AC を盲目的に全 PR に当てず、「観測性回復」「サイレント失敗予防新設」のような PR 本質に応じてゲートを選ぶ判断ロジック。 -->

**問題**: `kobaamd_review_security` のレビュー観点リスト（パターン 12「観測機構の自己観測責務」、シェルクォート規約、`set -u` + `trap` + `local` 互換性、サプライチェーン等）を全 PR に盲目的に適用すると、既存 WARN を呼び出し元 stderr に中継しただけの「観測性回復」PR にも「サイレント失敗予防機構の自己観測テスト」を要求してしまい、PR 本質と乖離した concern を量産しうる。

**対策**: `kobaamd_review_security` の判定では、PR diff の **性質を一次分類** してからゲート観点を選ぶ:

- **観測性回復**（既存 WARN / log を見えるようにしただけ）: パターン 12 の重い AC は適用範囲外。stderr 中継ロジックの正しさ・リーク確認に絞る
- **サイレント失敗予防機構の新設**（観測機構そのものの追加）: パターン 12 を全面適用。機構自身が `set -u` + `trap` + `local` で死なないこと、`|| true` でマスクされた結果が空一致しないこと、依存コマンド失敗のリカバリ系シナリオを smoke test に含むこと
- **クォート / 入力バリデーション系の補強**: `security-hardening` のクォート規約・`mktemp` 使用・`set -e/+e` の囲み・一時ファイルリーク無しを観点に

つまり**観点リストを上から舐めるのではなく、PR 本質を 1 行で要約して該当ゲートだけを当てる**。観点を選ぶ判断ロジック自体を `kobaamd_review_security` のプロンプトに明記し、wiki 化された観点を「いつ適用しないか」のフィルタも合わせて運用する。

**出所**: KMD-153 (PR #84) review_security が「観測性回復であり新規サイレント失敗予防機構ではないため §12 の重い AC は適用範囲外」と判断したケース

### パターン 20: shell script の小規模 surgical fix は main session 直接 Edit で十分
<!-- llm-context: < 30 行の `*.sh` 修正は Codex CLI を経由せず main session が直接 Edit する方が往復コストが見合う。CLAUDE.md の役割分担表「.swift は Codex」は shell script に拡張しない、という運用の明文化。 -->

**問題**: CLAUDE.md の役割分担表は「`.swift` ファイルを新規作成・編集するなら → Codex CLI に依頼」と書いているが、shell script (`*.sh`) について明示的な扱いがない。KMD-153 では main session が直接 Edit した（17 行追加 / 2 行変更）のは妥当な判断だったが、後続の subagent / 人間が判断するための基準が CLAUDE.md / wiki に書かれていないため再現性のあるルールになっていない。

**対策**: shell script の小規模 surgical fix（**目安 30 行未満 / 構造変更を伴わない**）は main session 直接 Edit を可とし、それ以上 / 構造変更を伴うものは Codex CLI 経由の `kobaamd_implement_code` に依頼する、という境界を明文化する。役割ディスパッチの正本は [[role-dispatch]] §4「近接ロールの境界」（shell script 行を追加）に置き、CLAUDE.md の役割分担表は本記事および role-dispatch を参照する形に揃える。

判断基準の例:

- 17 行追加 / 2 行変更で stdout/stderr 分離だけ入れる → main session 直接 Edit（KMD-153 の実例）
- 100 行超のリライト / 関数構造の大幅変更 / 複数ファイルにまたがる shell 改修 → Codex CLI 経由

`*.swift` は引き続き Codex CLI が原則（既存ルールどおり）。

**出所**: KMD-153 (PR #84)、`docs/wiki/articles/practices/role-dispatch.md` §4 の SSOT に対応

### パターン 21: 純粋リファクタ PR の動作等価性は制御フロー追跡で論証する
<!-- llm-context: `[carve]` / `[refactor]` / `[cleanup]` 的な PR では「動作に影響していないか」が主要確認事項。before/after の制御フローを trace して等価性を論証する観点を review_pr に明示することで、再現性ある APPROVE 品質を得る。 -->

**問題**: 通常の PR は「変更が正しいか」を確認するが、純粋リファクタ PR（KMD-186 の `MainActor.assumeIsolated` 二重ネスト解消等）では逆に「変更が動作に影響していないか」の等価性証明が主要確認事項になる。この観点を `kobaamd_review_pr` のプロンプトに明示していないと、通常の機能確認観点でレビューされて等価性の論証が省略されうる。

**対策**: `kobaamd_review_pr` のプロンプトに以下を追記する:

- PR タイトルまたは description に `[refactor]` / `[cleanup]` / `[carve from]` を検出したら、**「動作等価リファクタ」モードでレビュー**する
- 動作等価リファクタの主要観点: before/after の制御フローを 1 ステップずつ trace し、実行順序・条件分岐・副作用（キャプチャ変数・nil チェック・`@MainActor` 境界）が変化していないことを言語化して論証する
- 等価性論証が本文に含まれていれば、PRD AC 整合・影響範囲一致・[BREAKING] なしの 3 条件でクリーン APPROVE へ進める

**付帯事項（PRD-lite テンプレートへの反映）**: auto-carve 起票時の PRD-lite に「変更箇所: `<ファイル>:<L始>-<L終>`」フィールドを追加する。行番号まで明示されていると実装側（Codex CLI）が surgical 変更しやすく、reviewer がコラテラルダメージなしを diff で機械的に確認しやすくなる。KMD-186 はこの形式の PRD-lite を持ち、能動フェーズ（In Progress → Done）6 分で完了した。

**出所**: KMD-186 (PR #114)、`NSTextViewWrapper.swift` の `MainActor.assumeIsolated` 二重ネスト解消（純粋リファクタ、動作等価性を `queue: .main` クロージャ内の制御フロー trace で論証）


## Related

- [[mvvm-observable]] — パターン 2 の概念的背景
- [[prd-quality-cycle]] — パターン 1 / 7 / 15 の PRD への反映
- [[security-hardening]] — シェル変数クォート等のセキュリティ視点の再発防止 / パターン 12 の「サイレント失敗パターン」表との接続
- [[autonomous-pipeline-philosophy]] — パターン 13 / 14 の auto carve-out フローの設計意図
- [[wiki-reference-policy]] — wiki 経由で再発防止知見を引き継ぐ手順
- [[dependency-inversion-guard]] — パターン 9 の詳細とテンプレート
- [[autonomous-pipeline-philosophy]] — パターン 7 / 8 が機能する前提となるレビュー運用
- [[subagent-prompt-design]] — パターン 15 / 16 / 17 の subagent プロンプト設計への反映（KMD-120）
- [[role-dispatch]] — パターン 20 の shell script 小規模 fix 経路の SSOT（§4 近接ロールの境界）

## Sources

- docs/learnings/2026-04-28-KMD-4.md
- docs/learnings/2026-04-28-KMD-6.md
- docs/learnings/2026-04-29-KMD-20.md
- docs/learnings/2026-04-28-KMD-22.md
- docs/learnings/2026-05-05-KMD-54.md
- docs/learnings/2026-05-06-KMD-144.md
- docs/learnings/2026-05-08-KMD-120.md
- docs/learnings/2026-05-08-KMD-153.md
- docs/learnings/2026-05-15-KMD-186.md
