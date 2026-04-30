# PRD ストレージ

このディレクトリには、Linear (KMD team) で管理される各 issue に対応する詳細な PRD (Product Requirements Document) を Markdown で格納する。

## 命名規則

`<linear-issue-id>-<slug>.md`

例: `KMD-12-outline-panel.md`

## 作成タイミングとフローの関係

ステータスフローと PRD の関係は以下:

| 遷移 | PRD の状態 | 主な実行者 |
|---|---|---|
| draft → backlog | この遷移時に詳細 PRD を新規作成 | `kobaamd_create_prd` subagent（`/kobaamd_create_prd KMD-XX`）/ 人間 |
| `/kobaamd_research_create_ticket` → backlog（直入れ） | issue description に PRD-lite が含まれる。`docs/prd/` には作らない | `kobaamd_research_create_ticket` subagent |
| backlog → todo | 人間承認ゲート（priority/label 判定）。PRD は既に揃っている前提 | 人間 |

`/kobaamd_research_create_ticket` の出力（PRD-lite）で着手判断に十分と判断された場合は、`docs/prd/` に詳細 PRD を作らずそのまま todo に昇格する運用も許容する。詳細 PRD が必要と判断したら、`/kobaamd_create_prd KMD-XX` を実行して docs/prd/ に補強する。

## 配置

- `_template.md`: 新規作成時のテンプレート。実 PRD では先頭の `_` 抜きでファイル名を作る。
- `KMD-XX-<slug>.md`: 各 issue の PRD 本体。

## 編集ルール

- 完成した PRD はコミットして main にマージする
- PRD の更新は対応する Linear issue にコメントを追加することで履歴を残す
- 大幅変更（要件レベル）は新規 PRD として `KMD-XX-v2-<slug>.md` で残し、旧版は archived ディレクトリへ移す
