---
linear: KMD-143
parent: KMD-55
status: in-progress
created_at: 2026-05-06
author: kobaamd_implement_code (Claude Opus 4.7)
---

# [KB2] kobaamd_update_wiki lint ゲートの bash スニペット堅牢化（set -e セーフ / --fix exit code 反映）

## 1. 背景・目的

KMD-55（PR #65, kobaamd_update_wiki に ingest 時 lint ゲート追加）のレビューで
auto-carveable concern として残った改善項目。本タスクは prompt の robustness を
上げる単発改善で、別 PR で扱う。

`.claude/agents/kobaamd_update_wiki.md` の lint ゲート step（step 6）の bash
スニペットが、LLM が読んで実行する想定にもかかわらず以下の罠を抱えている:

1. **`set -e` 環境下で即死**: `./scripts/wiki/lint.sh --no-llm > "$NDJSON"` の
   直後に `LINT_EXIT=$?` を取っているが、`set -e` 状態だと exit 1（violations）
   で即死してしまい `LINT_EXIT` が更新される前にスクリプトが終わる
2. **`--fix` の exit 2 を握りつぶす**: 現状 `./scripts/wiki/lint.sh --fix --no-llm > /dev/null || true`
   で `--fix` の exit code を捨てている。`--fix` が内部エラー（exit 2）を返した
   ことが Final Report から判らず、再 lint が pass してしまうとデバッグが困難に
   なる
3. **(任意) `error` と `skipped` の commit 継続ポリシー**: 現状どちらも commit
   継続だが、運用次第では `error` のみブロックしたいケースがあるかもしれない

## 2. 機能要件

### 必須要件（AC1, AC2）

1. **set -e セーフな書き方に統一**

   - すべての `./scripts/wiki/lint.sh` 呼び出しを以下の形式に変更:
     ```bash
     LINT_EXIT=0
     ./scripts/wiki/lint.sh --no-llm > "$NDJSON" || LINT_EXIT=$?
     ```
     `|| LINT_EXIT=$?` 形式により、`set -e` 環境下でも exit 1（violations）が
     `||` の左辺で捕捉され、右辺の `LINT_EXIT=$?` が必ず評価される
   - 直後に `$?` を取る形は使わない（パイプラインが入った瞬間に壊れる）
   - `--fix` 実行も同様に `FIX_EXIT=0; ./scripts/wiki/lint.sh --fix ... || FIX_EXIT=$?`

2. **`--fix` の exit code を `FIX_EXIT` に保持し Final Report に反映**

   - `--fix` 単独 exit code を `FIX_EXIT` 変数で保持
   - 再 lint が pass しても、`FIX_EXIT != 0` の場合は Final Report の `lint:` 行に
     ブレッドクラムを残す:
     - `lint: pass-after-fix(--fix で N 件自動修正)`（既存）
     - `lint: pass-after-fix(--fix exit=2 だが再 lint で 0)`（新規）
   - `FIX_EXIT=0` で再 lint も pass の通常ケースは既存メッセージを使用

### オプション要件（AC3, 任意）

3. **`error` / `skipped` の commit 継続ポリシーを切り替え可能にする**

   - env var で挙動を選択できるようメモする（実装は最小限の prompt 文言のみで OK）:
     - `WIKI_INGEST_BLOCK_ON_ERROR=1` → `LINT_STATUS=error` で commit を中止
     - デフォルト（未設定 or `0`）→ 現状どおり commit 継続
   - `skipped`（lint.sh 不在）は別軸で `WIKI_INGEST_BLOCK_ON_SKIPPED=1` 用意

## 3. 受け入れ条件 (Acceptance Criteria)

- [ ] AC1: step 6.a の bash スニペットが `set -e` 環境下でも `LINT_EXIT` を
      正しく捕捉する書き方（`|| LINT_EXIT=$?`）に変更されている
- [ ] AC2: step 6.c の `--fix` 呼び出しで `FIX_EXIT` を別変数として保持し、
      Final Report の `lint:` 行に `pass-after-fix(--fix exit=2 だが再 lint で 0)`
      のようなブレッドクラムを残せるよう prompt が更新されている
- [ ] AC3（任意）: `WIKI_INGEST_BLOCK_ON_ERROR` / `WIKI_INGEST_BLOCK_ON_SKIPPED`
      env による commit 継続ポリシー切り替えが prompt に明記されている
- [ ] AC4: Final Report Format の `lint:` 行例に `pass-after-fix(--fix exit=2 だが再 lint で 0)`
      バリアントが追加されている
- [ ] AC5: 既存の Workflow step 1〜5 / 7、Constraints セクションは変わらない
- [ ] AC6: swift build が通る（Swift コードに触らないので回帰なし）

## 4. 影響範囲マップ

### 変更対象

| ファイル | 変更種別 | 備考 |
|---|---|---|
| `.claude/agents/kobaamd_update_wiki.md` | 変更 | step 6.a / 6.c の bash スニペット差し替え + Final Report Format の `lint:` 行例の追加 |
| `docs/prd/KMD-143-update-wiki-lint-gate-hardening.md` | 追加 | 本 PRD-lite |

### 変更してはいけない箇所（明示）

- **Swift コード一切**（Sources/** / Package.swift / Info.plist / project files）
- `kobaamd_update_wiki.md` の Workflow step 1〜5 / step 7 の中身（順序・引数・
  既存記事の更新ルール / 新規作成ルール / index.md / log.md の規約）
- `kobaamd_update_wiki.md` の Constraints セクション（ループ上限 5 ソース等）
- `kobaamd_update_wiki.md` の Input modes セクション
- step 6.b / 6.d / 6.e の判定ロジック・ステータス語彙（pass / pass-after-fix /
  fail / error / skipped）— 既存運用と互換であること
- `scripts/wiki/lint.sh` 本体・他 scripts
- `docs/wiki/articles/**`（wiki 記事本体）
- `docs/wiki/SCHEMA.md`
- `.claude/commands/kobaamd_lint_wiki.md` / `.claude/agents/kobaamd_review_postmortem.md`
- `kobaamd_review_postmortem` / `pipeline_weekly` の caller 側引数
- 他の `.claude/agents/*.md` / `.claude/commands/*.md`

## 5. テスト戦略

- 静的検証: `.claude/agents/kobaamd_update_wiki.md` を読み返して AC1〜AC5 を
  目視確認
- swift build: Swift コードは触らないが、CI 互換性確認のため一度実行
- 統合テスト: 本 PR では実走しない。後続の実 ingest で動作確認する

## 6. 参考

- `docs/prd/KMD-55-update-wiki-lint-gate.md` — 親 PRD
- KMD-55 PR #65 — レビューで concern として carve-out された経緯
