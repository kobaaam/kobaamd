---
linear: KMD-155
status: in-progress
created_at: 2026-05-09
author: kobaamd_implement_code (Claude Opus)
---

# section-context-check の cache 互換性検証と shell 側統一管理化

## 1. 背景・目的

KMD-150（PR #74）の `kobaamd_review_pr` で auto-carve-out された concern。
`scripts/wiki/lib/section-context-check.sh` は legacy 経路（`--legacy-api`）と
subagent 経路（既定 / `kobaamd_lint_section_context` Haiku 経由）の **両方が同じ
cache file (`.cache/wiki-lint.json`) を共有する**設計だが、実装は二重化されている:

- **legacy 経路**: shell 側で `content_hash` を `shasum -a 256` で計算し、
  `cache_lookup` / `cache_store` を直接呼んでいる。hash 入力は
  `"${relative_path}|H${level}|${title}|${body}"` で固定
- **subagent 経路**: agent (Haiku) の Bash 経由で同じ構造を書くようにと
  prompt に指示しているだけで、**hash 粒度（改行正規化・shasum コマンド・入力
  トリミング）の一致が保証されていない**

両者で hash が一致しない場合 `cache_lookup` が常に miss し、subagent 経路で毎回
全セクション再判定 → スループット劣化となる。さらに、agent 側で何らかの hash 不一致
が起きても気付ける手段がない（cache hit 率の観測も無い）。

本タスクでは `subagent 経路でも cache 読み書きを shell 側に集約する` ことで、
両経路の cache 互換性を構造的に保証する。

## 2. ターゲットユーザーとユースケース

- 開発者（kobaamd メンテナ）が `scripts/wiki/lint.sh` を実行したとき、`.cache/wiki-lint.json`
  に蓄積された判定結果が **経路に依らず再利用される**
- パイプライン (`pipeline_active` → wiki ingest → lint) が定期実行されたとき、
  キャッシュヒット率が安定し、Haiku 呼び出し回数が無駄に増えない

## 3. 機能要件

- 必須要件:
  1. **hash 計算は shell 側で一本化**: subagent 経路でも shell 側が事前にセクション抽出と
     hash 計算を行い、cache hit 分は subagent 起動前に判定済みに倒す
  2. **subagent には verdict 計算だけさせる**: 渡すのは未判定セクションのみ。
     subagent からは「verdict 結果 (NDJSON)」を受け取り、shell 側で cache に書き戻す
  3. **cache 構造は据え置き**: `{"section_context": {"<hash>": "<verdict>"}, "version": 1}` を
     維持し、legacy 経路で書き込んだエントリと subagent 経路で書き込んだエントリは衝突せず
     互換利用できる
  4. **動作確認**: 同じ wiki 記事を `--legacy-api` 経路と既定経路で連続実行したとき、
     2 回目以降は API/agent 呼び出しゼロで完了する（cache hit ログで確認）

- オプション要件:
  1. cache hit / miss / 経由を stderr に件数集計で出す（運用観測のため）
  2. agent prompt から「cache を書け」という記述を削除する（責務を明確化）

## 4. 非機能要件

- パフォーマンス: 既存 lint の所要時間を悪化させない（hash 計算が shell 側に増えるが、
  python によるセクション抽出は元々 shell 側にあるので追加負荷は最小）
- 互換性: 既存 `.cache/wiki-lint.json` の内容を温存。`version: 1` のまま
- 観測性: subagent 経路でも cache hit / miss 件数を stderr に出す

## 5. UI/UX

CLI のみ。出力フォーマット（NDJSON）と exit code は不変。

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `run_subagent` が呼ばれる前に shell 側でセクション抽出と hash 計算を実施し、
      cache hit したセクションは subagent に渡さない
- [ ] subagent には未判定セクションのリスト（または対象セクションのキー）を渡し、
      返り値（NDJSON）を shell 側で受け取って cache に書き戻す
- [ ] 同一記事を `--legacy-api` で 1 回 → 既定経路で 1 回実行したとき、
      2 回目は **subagent を起動せず** cache_hit のみで完了する
      （または起動しても全セクションがすでに判定済みで API 呼び出しが無いログが出る）
- [ ] subagent 内の prompt から「cache 書き込み責務」を削除し、shell 側に統一する
- [ ] stderr に `cache hit=N miss=M` の集計を出力する
- [ ] 既存 `.cache/wiki-lint.json` の構造を破壊しない（version も据え置き）

## 7. テスト戦略

- 単体テスト: なし（shell スクリプト）
- スナップショット: なし
- 手動確認:
  1. `.cache/wiki-lint.json` をバックアップ
  2. 1 記事を選んで 2 経路で連続実行: `bash scripts/wiki/lib/section-context-check.sh --file <path> --cache .cache/wiki-lint.json` を 2 回（既定経路）
  3. 2 回目の stderr に `cache hit=N miss=0` が出ることを確認
  4. `.cache/wiki-lint.json` をリセット → `--legacy-api` で 1 回 → 既定経路で 1 回。
     既定経路の 2 回目で cache hit になることを確認

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `scripts/wiki/lib/section-context-check.sh` | 変更 | `run_subagent` 内でセクション抽出 / hash 計算 / cache_lookup / cache_store を行うよう refactor。共通ヘルパを legacy/subagent 両方から呼ぶ形に整理 |
| `.claude/agents/kobaamd_lint_section_context.md` | 変更 | cache 書き込み責務を削除（shell 側に移譲したことを明記）。引数として「未判定セクションのリスト」を渡す方式に変更 |

**共有コンテナへの注意**:
- 対象ファイルを使っている他機能:
  - `scripts/wiki/lint.sh` が `section-context-check.sh` を呼ぶ。CLI 引数 / 出力 / exit code は不変なので影響なし
  - `kobaamd_lint_section_context` agent は `section-context-check.sh` 経由でしか起動されない
- 変更してはいけない箇所:
  - `section-context-check.sh` の **CLI 引数 (`--file` / `--cache` / `--model` / `--retries` / `--legacy-api` / `--dry-run`) と stdout NDJSON フォーマット**: 既存呼び出し元 (`scripts/wiki/lint.sh`) との契約
  - `.cache/wiki-lint.json` の構造 (`{"section_context": {"<hash>": "<verdict>"}, "version": 1}`) と既存エントリ
  - `legacy 経路の hash 計算ロジック`（`"${relative_path}|H${level}|${title}|${body}"` を `shasum -a 256`）
  - `legacy 経路の判定 prompt / system_preamble`: ここを動かすと既存 cache が全 miss になる
  - `kobaamd_lint_section_context` agent の **判定基準セクション** と「YES / NO の出力フォーマット」「ANTHROPIC_API_KEY を直接使わない」制約
  - `--allowedTools` の allowlist: shell→agent 起動時の権限制御（KMD-152 由来）。今回 shell 側に責務を寄せるので、agent が cache ファイルへ書く必要がなくなり結果的にスコープ縮小だが、**既存の allowlist にあるコマンド（`shasum` / `mkdir` / `mv` 等）はそのまま残す**（agent が hash や文字列処理に使う可能性を完全に否定しない）

### その他リスク

- 既存コードへの影響: `scripts/wiki/lint.sh` は CLI 引数 / NDJSON 出力で `section-context-check.sh` と契約しているので、シグネチャを保てば影響なし
- 互換性: `.cache/wiki-lint.json` のエントリは shell 側で計算した hash で書き込まれ続けるので、**legacy 経路で既に書き込まれた cache が subagent 経路でもそのまま hit する**
- 外部依存: なし（既存依存 `python3` / `jq` / `shasum` / `claude` CLI のみ）

## 9. 計測・成果指標

- subagent 経路で 2 回連続実行したとき、2 回目の `cache hit=` が記事のセクション数と一致する
- agent への入力プロンプトに「未判定セクションのリスト」が出てくる（cache hit したセクションは渡さない）

## 10. 参考資料

- `docs/wiki/articles/practices/wiki-reference-policy.md` の「1.2 Haiku ベースの lint / 判定タスクは Claude Code subagent 経由」
- 親 issue: KMD-150（PR #74、PRD: `docs/prd/KMD-150-section-context-via-subagent.md` 想定 / 不在なら issue 本文）
- 関連 carve-out: KMD-152（権限スコープ）/ KMD-153（stderr 中継）
