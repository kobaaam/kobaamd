---
description: アクティブ系パイプライン（30 分間隔想定）— 1チケットのライフサイクル全体（PRD→実装→検証→PR→レビュー→マージ→振り返り）を順に進める
---

以下を順番に実行してください。各ステップ失敗時は次に進む（部分成功許容）。

## ステップ 0a: Pre-run スナップショット（起動時 / 必須）

`/kobaamd_snapshot_state` を `source: "pre-run"` で実行する。これにより `.logs/pipeline_state.json` に現在の全 issue ステータスが記録され、前回との差分（人間による変更含む）が `.logs/pipeline_transitions.log` に追記される。

## ステップ 0b: Linear ステータス整合性チェック（起動時 / 必須）

Linear から `In Progress` と `in Review` の issue を取得し、実態と照合する。ログキャッシュの古い認識による WIP ブロックを防止する。

a. `./scripts/linear/lq.sh issue.list --team KMD --state "In Progress"` で In Progress の issue を列挙
b. 各 issue について `gh pr list --head <branch> --json number,state` で対応 PR の有無を確認
c. 以下の不整合パターンを検出・修正:
   - **PR がマージ済みなのに In Progress**: → Linear を `Done` に遷移
   - **PR が Close 済み（マージなし）なのに In Progress**: → Linear を `Todo` に戻す
   - **ブランチも PR もないのに In Progress**: → Linear を `Todo` に戻し、コメントで `[PIPELINE_SYNC] ブランチ/PR 未検出のため todo に戻しました` と記録
   - **ローカルブランチあり + リモート未push + PR なし + uncommitted（or 未push commit あり）**: → **halted recovery を起動**（KMD-30 incident type、後述 0c）
d. 修正があった場合は `.logs/pipeline_active.log` に `==== <日時> STATUS_SYNC: KMD-XX <旧状態> → <新状態> ====` を追記
e. 修正がなければ「整合性 OK」と報告して次へ

## ステップ 0b': No-op early return ガード（起動時 / 必須）

ステップ 0b でステータス整合性が取れた直後、以下のガード条件をすべて満たす場合は subagent を起動せずに即終了する。launchd 30 分毎の起動で no-op cycle が連続した場合の token 空費（CLAUDE.md ~8k tokens + subagent プロンプト）を削減するための最適化。

**ガード条件（すべて AND）**:

1. `Reviewed` 状態の issue が **0 件**
2. `Human in Review` 状態の issue が **0 件**
3. `in Review` 状態の issue が **0 件**
4. CONFLICTING な PR が **0 件**（`gh pr list --json number,mergeable --jq '[.[] | select(.mergeable == "CONFLICTING")] | length'`）
5. `draft` 状態の issue が **0 件**
6. `In Progress` 状態の issue が **1 件以上** OR `Todo` 状態の issue が **0 件**

**判定方法**:

```bash
REVIEWED=$(./scripts/linear/lq.sh issue.list --team KMD --state "Reviewed" --limit 1 --json | jq 'length')
HUMAN_IN_REVIEW=$(./scripts/linear/lq.sh issue.list --team KMD --state "Human in Review" --limit 1 --json | jq 'length')
IN_REVIEW=$(./scripts/linear/lq.sh issue.list --team KMD --state "in Review" --limit 1 --json | jq 'length')
DRAFT=$(./scripts/linear/lq.sh issue.list --team KMD --state "draft" --limit 1 --json | jq 'length')
IN_PROGRESS=$(./scripts/linear/lq.sh issue.list --team KMD --state "In Progress" --limit 1 --json | jq 'length')
TODO=$(./scripts/linear/lq.sh issue.list --team KMD --state "Todo" --limit 1 --json | jq 'length')
CONFLICTING=$(gh pr list --json number,mergeable --jq '[.[] | select(.mergeable == "CONFLICTING")] | length')
```

**早期終了処理**:

すべてのガード条件を満たす場合、`.logs/pipeline_active.log` に以下を追記して exit:

```
==== <ISO8601 日時> PIPELINE_ACTIVE_DONE: full no-op (early return, no subagent invocation) ====
  reviewed=0 human_in_review=0 in_review=0 conflicting=0 draft=0 in_progress=N todo=N
```

その後、最終レポートとして「PIPELINE_ACTIVE_DONE: full no-op (early return)」とだけ報告して終了する。**ステップ 0c 以降のすべてのステップはスキップする**。

ガード条件を一つでも満たさない場合は通常通りステップ 0c へ進む。

## ステップ 0c: halted recovery（自動 staged 救済 / 必須）

中断耐性として、`scripts/recovery/recover_halted.sh --auto` を起動する。これは In Progress 状態で:

- ローカルブランチがある（`feature/<KMD-XX>-*`）が
- リモート push されていない、または PR が未作成
- かつ uncommitted 変更や未 push commit が存在

というパターンを検出して、以下を自動実行:

1. ブランチに checkout → `swift build` で動作確認
2. build pass → `git add -A && git commit -m "<KMD-XX>: WIP commit by halted recovery (auto)"`（pre-commit hook を通す。`--no-verify` 禁止）
3. `git push -u origin <branch>`
4. `gh pr create --title "[HALTED-RECOVERED] <KMD-XX>: ..." --body "..."`
5. `halted-recovered` ラベル付与 + Linear を `in Review` に遷移
6. build fail / pre-commit hook 失敗時は `halted-broken` ラベル付与 + Linear に警告コメント、人間介入待ち

実行コマンド:

```bash
LQ_DRY_RUN=0 ./scripts/recovery/recover_halted.sh --auto
```

このステップで自動 PR 化された issue は通常通りフェーズ A の review_pr / review_security を通る。`[HALTED-RECOVERED]` プレフィックスと `halted-recovered` ラベルで識別可能なので、レビュアー（人間 / AI）は「中断された実装を引き継いだ PR」と認識すること。**Reviewed への直行は禁止**（人間ゲートは通常 PR と同じ）。

## フェーズ A: 既存 PR の処理

1. `/kobaamd_merge_pr` ← auto モード。以下を順に実行:
   - **Human in Review クリーンアップ**: PR がマージ済みなのに Human in Review に残留している issue を検出し Done に遷移
   - **reviewed → done**: reviewed にある issue の PR を main にマージして done に遷移

2. **コンフリクト解消（conflicting PR がある場合）**

   `gh pr list --json number,mergeable` で CONFLICTING な PR を検出。ある場合:
   a. 各 PR ブランチを `git checkout -b fix/resolve-<branch>` で作成し main にリベース
   b. コンフリクトを解消（AppCommand/AppViewModel 等の共有ファイルは全 case を保持する方針）
   c. `swift build` でビルド確認、失敗時は Codex CLI で修正
   d. 解消済みブランチを元のブランチ名で force push
   e. CONFLICTING が 0 件になったら次へ

3. **レビュー ↔ 修正ループ（in-progress がなくなるまで繰り返す / 最大5回）**

   毎ループで以下を順に実行する:
   a. `/kobaamd_review_pr --auto` ← in-review の issue を全件レビュー（クリーン APPROVE → Reviewed 直行 / [BREAKING] or concern>0 → Human in Review / fail>0 → In Progress）
   b. REQUEST_CHANGES が出た場合: `/kobaamd_fix_pr_comments --auto` ← 指摘を修正して in-review に戻す
   c. in-progress（REQUEST_CHANGES 起因）が 0 件になったらループ終了
   d. 5回繰り返しても in-progress が残る場合はループを抜け、残件を報告して人間にエスカレーション

4. **人間フィードバック対応（Human in Review / in Review に新しい人間コメントがある場合）**

   a. `./scripts/linear/lq.sh issue.list --team KMD --state "Human in Review"` と `./scripts/linear/lq.sh issue.list --team KMD --state "in Review"` で issue を取得
   b. 各 issue について `./scripts/linear/lq.sh comment.list KMD-XX` でコメントを時系列で取得
   c. **人間コメントの判定**: コメントの `user.email` が AI アカウント（`es57ster+claude@gmail.com`）以外であれば人間コメント
   d. **新規コメントの判定**: 最後の AI コメント（review_pr / rework_issue / fix_pr_comments の出力）より後に人間コメントがあれば「新規フィードバックあり」
   e. **新規フィードバックを 5 カテゴリに分類**（**ハイブリッド指示は複数カテゴリが共存可能**。コメント全文を読んで concern ごとに分類）:

      | カテゴリ | 判定の手がかり | 振り分け先 |
      |---|---|---|
      | **approval** | 「マージしてください」「OK」「承認」「そのままで」「了解」「進めて」など、肯定的な確定表現 | このカテゴリ単独なら → `Reviewed` 遷移 → `/kobaamd_merge_pr <KMD-XX>` |
      | **carve** | 「別チケット」「別起票」「別 PR で」「分けて」「後で」など、退避指示 | `/kobaamd_carve_concerns <KMD-XX>` で対象 concern を退避（carve_concerns が処理後の遷移まで担当） |
      | **rework_spec** | 仕様変更・追加要件・UI 変更指示（`「○○に変えて」「○○も対応して」`） | `/kobaamd_rework_issue <KMD-XX>` |
      | **rework_impl** | 実装の修正指示（バグ・既存挙動の修正。仕様は変えずに直す） | `/kobaamd_rework_issue <KMD-XX>` または `/kobaamd_fix_pr_comments <KMD-XX>` |
      | **question** | 質問・確認・「どう思う？」 | Linear に回答コメント。ステータスは `Human in Review` のまま |

   f. **ハイブリッド指示の処理順序**（複数カテゴリが共存する場合）:
      1. 先に **carve** を実行（`/kobaamd_carve_concerns` を起動して対象 concern を退避）
      2. 次に **rework_spec / rework_impl** が残っていれば実行（rework_issue / fix_pr_comments）。マージへは進まない
      3. rework が無く、残りが **approval** + **question** のみの場合:
         - approval → `Reviewed` 遷移 + `/kobaamd_merge_pr <KMD-XX>` 起動
         - question → 別途回答コメントを追加（マージとは独立）
      4. すべての分類について **「宣言だけで終わらせない」**。実行したアクションをすべて Linear コメントに記録（カテゴリ別に「実行: KMD-XX を Reviewed 遷移済み」「carve-out: KMD-YY 起票済み」など）

   g. 新規フィードバックがなければスキップ

5. `/kobaamd_merge_pr` ← レビュー後に reviewed に遷移した issue を即マージ

## フェーズ B: 新チケットの完全サイクル（**todo が尽きるか最大 5 サイクルまで繰り返す**）

カウンタ `cycle = 0`、上限 `MAX_CYCLES = 5` で以下のループを実行する。各サイクルで 1 チケットの完全サイクル（PRD → 実装 → 検証 → レビュー → マージ → 振り返り）を回し、次のサイクルに進む。

```
while cycle < MAX_CYCLES:
  cycle += 1
  ステップ 6 → 7 → 8 (break 条件あり) → 9 → 10 (break 条件あり) → 11
end while
```

各ステップ:

6. `/kobaamd_create_prd --auto` ← draft issue を全件 PRD 化して backlog に昇格（draft がなければスキップ）

7. **PRD レビュー ↔ 修正ループ**（ステップ 6 で PRD が作成された場合のみ / 最大5回）

   各 PRD 化された issue に対して以下をループ:
   a. `/kobaamd_review_prd <KMD-XX>` を実行
   b. PASS → ループ終了、次のステップへ
   c. REQUEST_REVISION → `/kobaamd_create_prd <KMD-XX>` で PRD を修正（backlog 状態のまま再実行、レビュー指摘コメントを自動読み取り）
   d. 修正完了後、a に戻って再レビュー
   e. 5回繰り返しても PASS しない場合はループを抜け、人間にエスカレーション

8. `/kobaamd_assign_work --auto` ← todo にあれば WIP=1 制御で1件選定し `kobaamd_implement_code` を起動

   **フェーズ B ループ break 条件**:
   - **todo 0 件** → これ以上進めるチケットがない。フェーズ B ループを break してステップ 12 へ
   - **WIP=1 制御で blocked**（In Progress / in Review に既存 issue がある状態でループ突入時 → 通常はサイクル内 merge で解消されているはずだが、merge 失敗等で残っているケース） → フェーズ B ループを break してステップ 12 へ

9. **実装後の検証**（ステップ 8 で implement_code が実行された場合のみ）

   a. **コードフォーマット**: 実装ブランチで `swift-format format -i -r Sources/` を実行し、差分があれば自動コミット（`style: apply swift-format`）
   b. `/kobaamd_validate_build` ← 実装ブランチで `swift build` + `swift test` を実行し Linear にコメント
   c. テスト失敗時は `kobaamd_implement_code` に修正を依頼して再度 validate_build を実行（最大3回）

10. **実装 PR のレビュー→マージ**（ステップ 8 で新規 PR が作成された場合のみ）

    a. `/kobaamd_review_pr` と `/kobaamd_review_security` を**並行実行** ← 機能レビューとセキュリティレビューを同時に行う
    b. セキュリティレビューが CRITICAL → issue を in-progress に戻し、`kobaamd_implement_code` で修正後に再度 10a から（最大3回）
    c. 機能レビューが REQUEST_CHANGES → `/kobaamd_fix_pr_comments` → 再レビュー（最大3回）
    d. 機能レビューの判定に応じて分岐:
       - **クリーン APPROVE（fail=0 / concern=0 / 非[BREAKING]）** → `kobaamd_review_pr` が `Reviewed` に直行済み。続けて `/kobaamd_merge_pr` を呼んで main に自動マージ → ステップ 11（振り返り）→ **次のサイクル**へ
       - **APPROVE [BREAKING] または concern>0** → `kobaamd_review_pr` が `Human in Review` に遷移済み。**フェーズ B ループを break** してステップ 12 へ（人間判断を待つ。次の todo に進むより、現チケットの結論を優先）
    e. 人間が `Human in Review` でコメント回答をした場合、フェーズ A ステップ 4 の「人間フィードバック対応」が次回起動時に検知して `rework_issue` ループを再開する。concern を別チケット化したい場合は人間が `/kobaamd_carve_concerns KMD-XX` を実行する。

11. **振り返り**（このサイクルでマージ完了した場合のみ）

    `/kobaamd_review_postmortem <KMD-XX>` ← done になった issue を振り返って `docs/learnings/` に出力。完了後、フェーズ B ループの先頭（ステップ 6）に戻って次のサイクルへ。

   **MAX_CYCLES に到達した場合**: ループを抜け、残 todo 件数を最終レポートに記載してステップ 12 へ。次回起動時に続きを処理する。

## ステップ 12: Post-run スナップショット（終了時 / 必須）

`/kobaamd_snapshot_state` を `source: "post-run"` で実行する。パイプライン実行による全ステータス遷移が `.logs/pipeline_transitions.log` に記録される。

各ステップの結果サマリと、次回起動時に注目すべき点（[BREAKING] 確認待ち / ループ上限超過 / 人間判断待ち）があれば 1〜2 行で報告してください。

事前確認:
- `source ~/.zshrc` で `LINEAR_API_KEY`/`OPENAI_API_KEY`/`GEMINI_API_KEY` を読み込む
- Linear I/O は `./scripts/linear/lq.sh` 経由（CLAUDE.md「Linear I/O ポリシー」参照）
- `gh` CLI 認証済み

対象想定: launchd で 1800 秒間隔起動 / または手動キックでも可
