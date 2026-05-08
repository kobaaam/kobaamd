# kobaamd 週次ステータスレポート — 2026-W23

**対象期間**: 2026-05-26（月）〜 2026-06-01（日）
**生成日時**: 2026-06-01
**データソース**: Linear KMD team / `.logs/token-retros/20260601T000034Z-168h.md`

---

## エグゼクティブサマリー

直近 7 日は `Done` が 3 件、`In Progress` が 1 件、`Todo` が 1 件で、レビュー待ちの滞留は 0 件だった。
一方で Codex token 使用は 7 日で約 150 万 tokens に達し、`kobaamd_pipeline_active` と `kobaamd_pipeline_daily` がほぼ全体を占めている。
そのため今週の主要アクションは、実装スループットよりも **パイプラインの payload 縮小と blocked 時の無駄打ち削減** に寄っている。

---

## 1. チケットフロー

### 1-1. 現在のステータス別件数

| ステータス | 件数 | チケット |
|---|---:|---|
| Backlog | 96 | KMD-214, 213, 212, 211, 210, 209, 208, 207, 206, 205 ... |
| Todo | 1 | KMD-173 |
| In Progress | 1 | KMD-176 |
| in Review | 0 | — |
| Human in Review | 0 | — |
| Reviewed | 0 | — |
| Done | 3 | KMD-203, KMD-40, KMD-31 |
| Canceled | 5 | KMD-201, KMD-149, KMD-147, KMD-34, KMD-33 |

**WIP**: 2 件（`Todo` + `In Progress` を除くレビュー滞留は 0）

### 1-2. 期間内の主要遷移

| チケット | タイトル | 遷移フロー | 備考 |
|---|---|---|---|
| KMD-203 | `[health] stale learnings PRs remain open after Done transition` | Backlog → Done | health 由来の追跡改善 |
| KMD-40 | `.entitlements ファイル骨格を追加（App Sandbox 化への布石）` | Backlog → Done | App Sandbox への下準備 |
| KMD-31 | `Diff ビューアの Pure Swift 化（Process() 排除）` | Backlog → Done | Process 依存削減 |
| KMD-176 | `usage 計測機構の堅牢化` | In Progress | 継続作業 |
| KMD-173 | `section-context-missing 2 経路の判定差分検証` | Todo | 次サイクル待ち |

### 1-3. 週間スループット

| 指標 | 値 |
|---|---:|
| 当週 Done 件数 | 3 |
| 当週 In Progress 件数 | 1 |
| 当週 Todo 件数 | 1 |
| レビュー待ち件数 | 0 |

---

## 2. リードタイム

> Linear の現在の取得形では `createdAt` と `updatedAt` が安定して取れるため、ここでは **作成→Done 時刻** をリードタイム近似として扱う。

### Done 3 件

| チケット | 作成 | Done | 所要時間 |
|---|---|---|---:|
| KMD-203 | 2026-05-21 18:16 UTC | 2026-05-25 02:16 UTC | 3.33 日 |
| KMD-40 | 2026-05-01 09:09 UTC | 2026-05-25 01:04 UTC | 23.66 日 |
| KMD-31 | 2026-04-30 01:37 UTC | 2026-05-25 03:26 UTC | 25.08 日 |

**平均 backlog→done**: **17.36 日**

---

## 3. AI vs 人間

### 3-1. ラベル分析

| ラベル | 件数 | 割合 |
|---|---:|---:|
| ai-research | 0 | 0% |
| Improvement | 1 | 1% |
| その他 | 105 | 99% |

> `ai-research` は現在の Linear 上では未使用。AI 起票は backlog への直接提案として扱われている。

### 3-2. 承認ゲート

| ゲート | 状況 |
|---|---|
| draft → backlog | 計測対象なし |
| backlog → todo | 人間承認待ちの issue が 1 件 |
| Human in Review | 0 件 |

---

## 4. 失敗率・レビューラウンド

### 4-1. 差し戻し

| 指標 | 値 |
|---|---:|
| in review → in progress 差し戻し | 0 件 |
| 平均レビューラウンド数 | 0.0 |

レビュー待ちが 0 件なので、今週はレビュー差し戻しが発生していない。

---

## 5. LLM コスト目安

**Codex 7 日合計: 1,508,635 tokens**

| API | Calls | Estimated tokens |
|---|---:|---:|
| Claude | 4 | 0 |
| Codex | 13 | 1,508,635 |
| Gemini | 0 | 0 |

### トップ消費

| Bundle | Calls | Estimated tokens |
|---|---:|---:|
| `kobaamd_pipeline_active` | 6 | 786,983 |
| `kobaamd_pipeline_daily` | 7 | 721,652 |

**判定**: コストは `active` / `daily` に集中。weekly pipeline の改善対象は実装追加より `run_bundle.sh` の入力圧縮が優先。

---

## 6. 注目チケット

| 優先度 | チケット | 状況 | 推奨アクション |
|---|---|---|---|
| 高 | KMD-176 | In Progress | usage 計測の堅牢化を完了して次回 retro の観測精度を上げる |
| 高 | KMD-173 | Todo | 次サイクルで着手可否を判断する |
| 高 | KMD-215 | Backlog | `run_bundle.sh` の Codex payload 縮小を実装候補として起票済み |

---

## 7. 翌週の推奨アクション

1. `run_bundle.sh` の payload 縮小を優先実装する
2. blocked / rate-limit 状態では non-critical 実行を skip する
3. `KMD-176` を完了させて usage 観測の精度を上げる
4. レビュー待ち 0 の状態を維持しつつ Todo を 1 件ずつ消化する

