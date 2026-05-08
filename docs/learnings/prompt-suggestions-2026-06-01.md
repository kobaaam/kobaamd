# Prompt / Budget Suggestions — 2026-06-01

対象: `kobaamd_*` pipeline / subagent prompts
入力: 2026-06-01 の token retro と直近 learnings

---

## 1. `run_bundle.sh` の Codex payload を縮小する

- 対象: `kobaamd_pipeline_active`, `kobaamd_pipeline_daily`
- 変更案: ログ / diff / 履歴をそのまま渡さず、必要行数だけを deterministic に切り詰める前処理を追加する
- 理由: 直近 7 日の Codex 消費の大半がこの 2 バンドルに集中しているため
- 期待効果: 平均 tokens/call を下げ、blocked 時の無駄打ちも減る

## 2. blocked / rate-limit 時は non-critical 実行を skip する

- 対象: `kobaamd_pipeline_active`
- 変更案: 既知の blocked flag がある場合、review 継続や新規実装を次回に defer し、再実行回数を抑える
- 理由: 失敗が見えている実行に高価な `gpt-5.4` を使うのは budget waste になりやすい
- 期待効果: 連続失敗時の token burn を止める

## 3. risky bug / cleanup issue では「代替案の不採用理由」を必須化する

- 対象: `kobaamd_research_create_ticket`, `kobaamd_review_pr`
- 変更案: PRD / レビューのテンプレに「採用しなかった選択肢」と「不採用理由」を 1 行で書かせる
- 理由: KMD-151 のような小さな修正でも race window や wait loop の検討を先に済ませると、後段の rework を減らしやすい
- 期待効果: risky issue の再レビュー回数を下げる

## 実装メモ

- まずは `run_bundle.sh` 側の入力整形を優先
- 次に `kobaamd_pipeline_active` の blocked 判定を追加
- prompt テンプレの変更は後追いで十分

