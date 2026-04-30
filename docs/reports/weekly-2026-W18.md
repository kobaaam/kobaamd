# kobaamd 週次ステータスレポート — 2026-W18

**対象期間**: 2026-04-21（月）〜 2026-04-27（日）
**生成日時**: 2026-04-27
**データソース**: Linear MCP (kobaamd チーム / KMD)

---

## エグゼクティブサマリー

プロジェクト発足から初週。Linear チケット管理を導入し、21件のチケットが起票された。
KMD-2（アウトラインパネル）が **当週唯一の Done** となり、startedAt から completedAt まで約45分というスピードで完了した。
PDF書き出し（KMD-3）・Markdownオートフォーマット（KMD-11）・TODO管理（KMD-7）の3件が in Review で週を越し、**ボトルネックはレビュー〜Human in Review フェーズ** にある。

---

## 1. チケットフロー

### 1-1. 現在のステータス別件数（アーカイブ済み除く・2026-04-27時点）

| ステータス | 件数 | チケット |
|---|---|---|
| Draft | 6 | KMD-14, 15, 16, 17, 18, 19, 20, 21（一部重複注意） |
| Backlog | 8 | KMD-4, 5, 6, 8, 9, 10, 12, 13 |
| Todo | 0 | — |
| In Progress | 0 | — |
| in Review | 3 | KMD-3, 7, 11 |
| Human in Review | 0 | — |
| Reviewed | 0 | — |
| Done | 1 | KMD-2 |
| Canceled / Duplicate | 0 | — |
| **合計（活性）** | **18** | |
| アーカイブ済み | 1 | KMD-1（テスト用、アーカイブ済み） |

> **補足**: Draft の内訳は KMD-14, 15, 16, 17, 18, 19, 20, 21 の8件。上表の Draft 行は8件に訂正。
> 正確な内訳: Draft=8, Backlog=8, in Review=3, Done=1 / 合計 **20件**（KMD-1アーカイブ含め21件起票）。

### 1-2. 期間内の主要遷移

| チケット | タイトル | 遷移フロー | 備考 |
|---|---|---|---|
| KMD-2 | アウトラインパネル | Backlog → In Progress → **Done** | 当週完了唯一件 |
| KMD-3 | PDF書き出し | Backlog → In Progress → **in Review** | 実装完了・PR出し済み |
| KMD-7 | TODO管理 | Backlog → In Progress → **in Review** | 実装完了・PR出し済み |
| KMD-11 | Markdownオートフォーマット | Backlog → In Progress → **in Review** | 実装完了・PR出し済み |
| KMD-9〜13 | 新機能群 | 起票 → **Backlog** | AI研究員が一括起票 |
| KMD-17〜21 | 新機能群 | 起票 → **Draft** | AI研究員が一括起票（2026-04-27） |

### 1-3. 週間スループット

| 指標 | 値 |
|---|---|
| 当週新規起票数 | 20件（KMD-1〜21、KMD-1はアーカイブ） |
| 当週 Done 件数 | **1件**（KMD-2） |
| 当週 in Review 到達数 | **3件**（KMD-3, 7, 11） |
| WIP（In Progress + in Review） | **3件** |

---

## 2. リードタイム

> **注意**: プロジェクト発足初週のため、完了サンプルは KMD-2 の1件のみ。統計的有意性は低い。

### KMD-2（唯一のDone）

| フェーズ | 開始 | 終了 | 所要時間 |
|---|---|---|---|
| 起票（createdAt） | 2026-04-25 08:03 | — | — |
| 実装開始（startedAt） | 2026-04-25 09:26 | — | 起票から約83分 |
| 完了（completedAt） | 2026-04-25 10:11 | — | 実装開始から約45分 |
| **backlog → done 合計** | | | **約2時間8分** |

### in Review 中チケットの経過日数（2026-04-27時点）

| チケット | In Progress 開始 | in Review 到達（推定） | 経過日数 |
|---|---|---|---|
| KMD-3 (PDF書き出し) | 2026-04-25 16:46 | 同日〜翌日 | **約1.3日** |
| KMD-7 (TODO管理) | 2026-04-25 13:21 | 同日 | **約1.5日** |
| KMD-11 (Markdownフォーマッタ) | 2026-04-25 13:59 | 2026-04-25 14:10 | **約1.4日** |

**平均 in Review 滞留時間**: 約1.4日（全件 Human in Review ゲートを未通過）

---

## 3. AI vs 人間

### 3-1. ラベル分析

| ラベル | 件数 | 割合 |
|---|---|---|
| Feature | 15件 | 75% |
| Bug | 1件 | 5% |
| Improvement | 1件 | 5% |
| ラベルなし | 4件 | 20% |

> `ai-research` ラベルは現時点の KMD チームに存在しない（設計上は使用予定）。
> 当週起票チケットは全て `hiroshi kobayashi`（人間）または AI エージェント経由での起票。
> **AI 起票比率**: KMD-9〜13（Backlog群）、KMD-17〜21（Draft群）は kobaamd_research_create_ticket による自律起票と判断される（同時刻バッチ起票パターン）。推定 **AI自律起票 ≒ 10件 / 全20件 = 50%**。

### 3-2. 承認ゲートの状況

| ゲート | 状況 |
|---|---|
| draft → backlog 承認 | KMD-9〜13 は Backlog に直接配置（`ai-research` ラベルなしで人間承認済みとみなす） |
| Human in Review | 現在 0 件（in Review 3件が待機中） |
| ai-research ラベル運用 | 未稼働（ラベル自体が Linear に未作成） |

**承認待ち時間（推定）**: in Review → Human in Review ゲートが未設定のため計測不能。KMD-3, 7, 11 は約1〜2日待機中。

---

## 4. 失敗率・レビューラウンド

### 4-1. in review → in progress 差し戻し件数

| 指標 | 値 |
|---|---|
| 当週差し戻し件数 | **0件** |
| 平均レビューラウンド数 | **1.0**（全件初回レビュー中） |

> 初週のため差し戻しなし。KMD-2 は直接 Done に遷移（Human in Review スキップ）。

### 4-2. ビルド/テスト失敗

Linear コメントに kobaamd_validate_build の実行記録なし。ビルド失敗件数は **計測不能**。
Git コミット履歴から `feature/KMD-3-pdf-export` ブランチが現在 in Review 相当であることを確認。

---

## 5. LLM コスト目安

**未計測**

計測手段が確立していない。以下の計測方法を次スプリントで導入推奨：

- Codex CLI: `~/.codex/` のリクエストログから token 数を集計
- Gemini: `googleapis.com` へのリクエストを Proxy でカウント
- Claude Code: `~/.claude/` の usage ログを参照（存在する場合）

---

## 6. 注目チケット（要アクション）

| 優先度 | チケット | 状況 | 推奨アクション |
|---|---|---|---|
| 高 | KMD-3 (PDF書き出し) | in Review 1.3日経過 | Human in Review → Reviewed へ手動遷移を依頼 |
| 高 | KMD-7 (TODO管理) | in Review 1.5日経過 | 同上 |
| 高 | KMD-11 (Markdownフォーマッタ) | in Review 1.4日経過 | 同上 |
| 中 | KMD-16 (自動アップデート) | Draft・PRDなし | PRD化 or Backlog 昇格判断 |
| 中 | KMD-15 (レイアウト崩れ) | Bug・Draft放置 | バグとして優先昇格を検討 |
| 低 | ai-research ラベル | Linear未作成 | ラベル作成して承認フローを稼働させる |

---

## 7. 翌週の推奨アクション

1. **KMD-3, 7, 11 を Human in Review → Reviewed → Done に進める**（ボトルネック解消）
2. **`ai-research` ラベルを Linear に作成**してパイプライン承認フローを正式稼働
3. **KMD-15（バグ）を draft から Backlog/Todo に昇格**し修正着手
4. **kobaamd_validate_build を KMD-3, 7, 11 で実行**してビルド確認を記録に残す
5. Todo 件数が 0 のためスループットが止まる恐れあり → KMD-4 or KMD-5 を Todo 承認

---

## 付録：全チケット一覧（2026-W18末時点）

| ID | タイトル | ステータス | Priority | ラベル |
|---|---|---|---|---|
| KMD-2 | アウトラインパネル | Done | Medium | Feature |
| KMD-3 | PDF書き出し | in Review | Medium | Feature |
| KMD-7 | TODO管理 | in Review | — | — |
| KMD-11 | Markdownオートフォーマット | in Review | Low | Feature |
| KMD-4 | AIインライン補完ストリーミング | Backlog | Medium | Feature |
| KMD-5 | TreeSitterシンタックスハイライト | Backlog | Medium | Feature, Improvement |
| KMD-6 | クイックインサート | Backlog | Medium | Feature |
| KMD-8 | Confluence同期 | Backlog | — | — |
| KMD-9 | カスタムカラーテーマ | Backlog | Low | Feature |
| KMD-10 | Quick Open (⌘P) | Backlog | Low | Feature |
| KMD-12 | フォーカスモード | Backlog | Low | Feature |
| KMD-13 | HTMLエクスポート | Backlog | Low | Feature |
| KMD-14 | ファイルDnD | Draft | — | — |
| KMD-15 | レイアウト崩れ（Bug） | Draft | — | Bug |
| KMD-16 | 自動アップデート | Draft | — | — |
| KMD-17 | Rendered Markdown Diff Viewer | Draft | Low | Feature |
| KMD-18 | YAML Frontmatter Editor | Draft | Low | Feature |
| KMD-19 | マルチターンAIチャットサイドバー | Draft | Low | Feature |
| KMD-20 | ファイルテンプレートシステム | Draft | Low | Feature |
| KMD-21 | エディタ/プレビュー同期スクロール | Draft | Low | Feature |
| KMD-1 | 【テスト】Linear MCP接続確認 | (アーカイブ) | Low | — |
