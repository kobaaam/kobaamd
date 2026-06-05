---
status: active
updated: 2026-06-05
phase: 2-ux
owner: Grok (設計) / Composer (実装) / Gemini (要件・UI 任意)
---

# Re-concept 実行計画 — モデル分担

## 役割分担

| 役割 | 担当 | 成果物 |
|------|------|--------|
| 要件・PRD・UI ラフ | **Gemini**（任意） | PRD 追記、`.mockups/` 更新、Settings 文言 |
| 設計・ADR・Spike・実装仕様 | **Grok** | ADR、依存グラフ、Composer handoff、Linear コメント |
| コード・テスト・ビルド | **Composer** | PR、`swift build` / `swift test` |

## 依存順（WIP=1 想定）

```
KMD-218 (PRD/ADR) ──► KMD-220 (E1 shell) + KMD-231 (flag)
        │
        └──► KMD-219 (SwiftTerm PoC) ──► KMD-225 ──► KMD-226
KMD-221 ──► KMD-222 ──► KMD-223 ──► KMD-224
KMD-224 + KMD-227 ──► KMD-228, KMD-232
```

**Phase 1（完了）**: KMD-219〜228, 220〜224, 231 — `feature/e1-reconcept-shell`。棚卸し: [KMD-e1-ticket-triage-2026-06-05.md](./KMD-e1-ticket-triage-2026-06-05.md)

**Phase 2（現在）**: Terminal（中央）× Preview × Editor 共存 UX

```
KMD-238 (merge)     KMD-234 (PRD UX) ──► KMD-235 (右 Split)
                              └──► KMD-236 (フォーカス)
                              KMD-235 ──► KMD-237 (拡張子別デフォルト)
KMD-229 (Quick Open スコープ) — 並行可
```

**Phase 3（保留）**: KMD-230, KMD-239（worktree）, KMD-233（旧 UI 削除）

## Tracer Bullet 1 — Composer 着手チケット

- 仕様: [KMD-220-composer-handoff.md](./KMD-220-composer-handoff.md)
- ブランチ: `feature/e1-reconcept-shell`（`main` から作成。CSV ブランチとは分離）
- Linear: KMD-220, KMD-231

## Gemini に依頼する場合（テンプレ）

```
kobaamd E1 Re-concept。参照: docs/prd/KMD-218-e1-reconcept.md, .mockups/prototype-e1-flow.html

1. Settings「実験的 UI」セクションの文言（日本語・英語）
2. Session レール空状態・worktree 0 件のコピー
3. Viewer タブ順序のラベル（Rendered / Source / D2 / Diff / CSV）と a11y ヒント

出力: Markdown のみ。コードは書かない。
```

## 人間 HITL ゲート

- [ ] PRD §5（Editor = 右 Source）— 承認後 KMD-218 → Backlog/Done
- [ ] ADR-0013 — proposed → accepted
- [ ] Tracer Bullet 1 マージ後、実機で flag 切替確認