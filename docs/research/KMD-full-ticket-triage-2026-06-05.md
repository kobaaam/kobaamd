---
status: active
updated: 2026-06-05
owner: Grok（全チーム棚卸し）
scope: Linear team KMD（プロジェクト横断）
---

# KMD 全チケット棚卸し（2026-06-05）

## エグゼクティブサマリ

| 指標 | 値 |
|------|-----|
| **アクティブ issue** | **128**（API 非アーカイブ分） |
| ID レンジ | KMD-12 〜 KMD-239（欠番 ≒ 過去 Done/Archived） |
| 状態内訳 | Backlog 105 / Reviewed 7 / Done 5 / Todo 3 / draft 2→0 / In Progress 1 / Canceled 5→7 |
| Linear プロジェクト紐付 | Re-concept 17件 / **未紐付 111件** |
| 戦略的フォーカス | **E1 Phase 2**（Terminal × Editor × Preview） |

**結論:** バックログの 82% は「将来価値あり・今は触らない」。WIP は **KMD-176**（infra）+ **E1 P2 入口（KMD-234/238）** に集中すべき。[ED]/[KB] ロードマップは E1 安定まで凍結推奨。

## 今すぐ（🔥）

| ID | 状態 | 内容 |
|----|------|------|
| **KMD-176** | In Progress | usage 計測堅牢化（パイプライン WIP） |
| **KMD-234** | Todo | [E1-P2] PRD: Terminal × Editor × Preview |
| **KMD-238** | Todo | merge `feature/e1-reconcept-shell` → main |
| **KMD-217** | Backlog ← draft | Epic（Phase 2 コメント追記済み） |

## 次（▶️）

- **E1 マージ待ち:** KMD-218, 220–224, 231（Reviewed）→ main マージ後 Done + アーカイブ
- **E1 完了待ちアーカイブ:** KMD-219, 225–228（Done）
- **E1 P2 実装:** KMD-235, 236, 237（親 KMD-234 PRD 後）
- **E1 並行可:** KMD-229（Quick Open スコープ）, KMD-232（Tart E2E）

## 後（⏸️）

- **[ED] ロードマップ** KMD-70, 74–89（17件）— 旧 3ペイン前提。E1 Viewer と重複する KaTeX/Callout 等は P2 以降で統合判断
- **[KB] ロードマップ** KMD-44, 56–64, 173（11件）— SQLite FTS / ingest。E1 の Files+Viewer 安定後
- **E1 P3+** KMD-230, 233, 239（Outline 配置 / ドキュメント / worktree 復活）

## アイスボックス（🧊）

- **AI プロダクト** KMD-36–39, 95–99, 100, 102–104, 116 等 — E1 の「エージェント作業 UI」が固まってから
- **Cursor/Zed port** KMD-210–214 — 調査バックログ。実装優先度は E1 P2 より低

## 取消・整理済み（❌）

| ID | 操作 |
|----|------|
| KMD-33, 34 | 既存 Canceled（テスト） |
| KMD-147, 149, 201 | 既存 Canceled（BLOCKED） |
| **KMD-216** | **Canceled**（空 GitHub payload・無効チケット） |
| **KMD-204** | **Canceled**（KMD-201 と重複 BLOCKED・related リンク済み） |

## バケット別件数

| バケット | 件数 | 方針 |
|----------|------|------|
| E1 Re-concept | 23 | **最優先**（Epic + 子 + P2/P3） |
| Pipeline / Infra | 23 | パイプライン稼働に必要なものだけ随時 |
| AI Product | 20 | アイスボックス |
| Editor [ED] | 17 | E1 後に再評価 |
| Misc | 14 | 個別判断 |
| Knowledge Base [KB] | 11 | E1 後 |
| Viewer / Preview | 9 | P2 と統合検討 |
| Carve-outs | 15 | 親 issue 完了まで保持 |
| AI Agent Ports | 5 | アイスボックス |
| Navigation / Sidebar | 3 | E1 P3（KMD-230）と整合 |
| Blocked | 2 | 外部キー・quota 解消まで待ち |
| Wiki / LLM | 1 | infra と並行可 |

## E1 詳細

Phase 1 判定・Phase 2 チケット設計は別紙:

- [KMD-e1-ticket-triage-2026-06-05.md](./KMD-e1-ticket-triage-2026-06-05.md)

## 推奨オペレーション（Linear 衛生）

1. **プロジェクト紐付:** KMD-234〜239 を `Re-concept: E1 Terminal + Knowledge Viewer` に移す（現状 parent のみ）
2. **アーカイブ:** Done の KMD-219, 225–228 はマージ確認後 `kobaamd_archive_done` 対象
3. **Reviewed → Done:** KMD-218, 220–224, 231 は PR マージ（KMD-238）後に遷移
4. **Backlog 凍結ラベル（任意）:** `[ED]`/`[KB]`/`Cursor port` に `deferred-post-e1` 相当のラベル付与
5. **重複掃除:** 親 issue が Archived の carve-out（KMD-94 等）は親子リンク監査

## Linear へ適用した変更（本棚卸し）

- `KMD-217` → **Backlog** + Phase 2 コメント
- `KMD-216` → **Canceled**
- `KMD-204` → **Canceled** + KMD-201 related + コメント

## 全件一覧

<!-- generated from /tmp/kmd-all-issues.json 2026-06-05 -->## 全件一覧（128 active）

| ID | 状態 | バケット | 判定 | タイトル |
|----|------|----------|------|----------|
| KMD-12 | Backlog | Misc | 📌 残す（Backlog） | Add focus mode (distraction-free writing) with typewriter scroll |
| KMD-13 | Backlog | Misc | 📌 残す（Backlog） | Add HTML export with custom CSS template selection |
| KMD-18 | Backlog | Misc | 📌 残す（Backlog） | Add YAML frontmatter editor panel for AI-generated document metadata |
| KMD-21 | Backlog | Misc | 📌 残す（Backlog） | Add editor/preview synchronized scroll with position lock |
| KMD-33 | Canceled | Misc | ❌ 済み取消 | テストチケット：MCP接続確認 |
| KMD-34 | Canceled | Misc | ❌ 済み取消 | テストチケット（パイプライン動作確認用） |
| KMD-36 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | AI インラインポップオーバーをカーソル位置に追従表示する |
| KMD-37 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | AI ポップオーバーのレイアウト不一致とキーボードショートカット到達性を改善 |
| KMD-38 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | AI インラインポップオーバー: API キー未設定時の送信ガードを追加 |
| KMD-39 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | AI インラインポップオーバー: バックスペース長押し時の誤閉じリスクを検証・修正 |
| KMD-44 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB] kobaamd ナレッジベース整備（Phase 1〜4） |
| KMD-56 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB3] SQLite 検索機構の導入（Cosmos KB 先行学習） |
| KMD-57 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB3] SQLite FTS5 スキーマ設計 |
| KMD-58 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB3] ingest スクリプト実装（チャンク分割 + Contextual prefix 生成 + FTS5 投入） |
| KMD-59 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB3] 検索 CLI scripts/wiki/search.sh の実装 |
| KMD-60 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB3] Phase 1 との AB ベンチマーク |
| KMD-61 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB3] kobaamd_update_wiki と検索インデックスの統合 |
| KMD-62 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB3] 効果測定レポートと Cosmos KB 設計指針の wiki 記事化 |
| KMD-63 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB4] kobaamd エディタの KB 機能追加（Wiki-link / Backlinks / タグ / MCP公開） |
| KMD-64 | Backlog | Knowledge Base [KB] | ⏸️ 後（KB ロードマップ） | [KB4] Wiki-link [[...]] のレンダリングと autocomplete |
| KMD-70 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED] kobaamd エディタ品質向上ロードマップ |
| KMD-74 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-B] プレビュー品質向上（KaTeX / Callouts / 拡張 Markdown / コードブロック装飾） |
| KMD-75 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-B] KaTeX 数式レンダリング（インライン + ブロック） |
| KMD-76 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-B] GFM Callouts（NOTE / TIP / WARNING / CAUTION / IMPORTANT） |
| KMD-77 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-B] 拡張 Markdown 構文（==highlight== / ^sup^ / ~~sub~~ / :emoji: / [TOC]） |
| KMD-78 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-B] コードブロック装飾の強化（27言語 / 行番号 / diff 強調 / コピーボタン） |
| KMD-79 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-C] 体験向上（インタラクション / PDF Export / QuickLook / 外部変更監視 / 増分レンダリング） |
| KMD-80 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-C] プレビュー内インタラクション（チェックボックス / 画像 zoom / 脚注ホバー / ジャンプ） |
| KMD-81 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-C] PDF エクスポート（ページブレーク対応） |
| KMD-82 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-C] QuickLook 拡張（Finder で Space キーでプレビュー） |
| KMD-83 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-C] ファイル外部変更の監視・autoreload |
| KMD-84 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-C] プレビューの増分レンダリング |
| KMD-85 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-D] 高度機能（Multibuffer / プレビュー専用テーマ / 双方向スクロール / Scratchpad） |
| KMD-86 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-D] Multibuffer（横断編集） |
| KMD-87 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-D] プレビュー専用フォント・テーマ設定 |
| KMD-88 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-D] アウトライン双方向同期スクロール |
| KMD-89 | Backlog | Editor [ED] | ⏸️ 後（ED ロードマップ・E1 安定後） | [ED-D] Scratchpad（メニューバー常駐） |
| KMD-91 | Backlog | Wiki / LLM | 📌 残す（Backlog） | [wiki] ヘルパー未整備期間の自動処理ガイダンスを SCHEMA / wiki-reference-policy で整合させる |
| KMD-92 | Backlog | Misc | 📌 残す（infra・随時） | scripts/wiki/load_all.sh のトークン推定を日本語対応にする |
| KMD-93 | Backlog | Misc | 📌 残す（infra・随時） | scripts/wiki/load_all.sh のリグレッションテスト整備（bats/shellcheck） |
| KMD-94 | Backlog | Carve-outs | 📌 残す（carve-out・親完了後） | scripts/wiki/ask.sh の引数バリデーションと文書整合（KMD-47 carve-out） |
| KMD-95 | Backlog | AI Product | 📌 残す（carve-out・親完了後） | AI インライン補完のカーソル直下追従精度を改善（KMD-42 carve-out） |
| KMD-96 | Backlog | AI Product | 📌 残す（carve-out・親完了後） | AI インライン補完のスクロール追従ジッタ解消（KMD-42 carve-out） |
| KMD-97 | Backlog | AI Product | 📌 残す（carve-out・親完了後） | AI インライン補完の VoiceOver 通知対応（KMD-42 carve-out） |
| KMD-98 | Backlog | AI Product | 📌 残す（carve-out・親完了後） | AI インライン補完 60fps 機械検証テスト（AC8b / KMD-42 carve-out） |
| KMD-99 | Backlog | AI Product | 📌 残す（carve-out・親完了後） | AI 補完開始時の {{プロンプト}} 削除 Undo グループ化（KMD-42 carve-out） |
| KMD-100 | Backlog | Viewer / Preview | 🧊 アイスボックス（AI 機能・E1 後） | Add streaming AST auto-healer for AI-generated Markdown preview |
| KMD-101 | Backlog | Viewer / Preview | ⏸️ 後（Viewer 磨き込み） | Add conversational refinement for Mermaid/D2 diagram blocks |
| KMD-102 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | Add App Intents and Services menu integration for headless AI capture |
| KMD-103 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | Add AI provenance tracking and per-paragraph regeneration |
| KMD-104 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | Add local CoreML embedding-based RAG over workspace notes |
| KMD-105 | Backlog | Viewer / Preview | ⏸️ 後（Viewer 磨き込み） | Viewer モードの動的アイコン化（モード視認性の改善） |
| KMD-106 | Backlog | Viewer / Preview | ⏸️ 後（Viewer 磨き込み） | Viewer モード往復・混合パターンのテスト網羅 |
| KMD-109 | Backlog | Misc | 📌 残す（Backlog） | UpdateCheckState の Combine 購読を assign(to: &$canCheckForUpdates) 形式に置き換え retain c |
| KMD-110 | Backlog | Misc | 📌 残す（Backlog） | UI 文字列の三点リーダーを HIG 準拠の U+2026 (…) に統一 |
| KMD-111 | Backlog | Misc | ⏸️ 後（Viewer 磨き込み） | テーマ切替時の Markdown プレビュー即時反映 (debounce バイパス + JS による <style> 差し替え) |
| KMD-112 | Backlog | Viewer / Preview | ⏸️ 後（Viewer 磨き込み） | D2 プレビューもテーマ切替に追従させる (D2PreviewView の onChange 駆動経路追加) |
| KMD-113 | Backlog | Misc | 📌 残す（Backlog） | テーマ切替時に 0.2s クロスフェードを追加する (HIG 整合の磨き込み) |
| KMD-114 | Backlog | Misc | ⏸️ 後（Viewer 磨き込み） | MarkdownWebView: callAsyncJavaScript の completion handler でサイレント失敗を解消する |
| KMD-115 | Backlog | Viewer / Preview | ⏸️ 後（Viewer 磨き込み） | D2 sanitizeSVG: SVG XSS 境界ベクター（use/xlink:href/foreignObject/animate）のカバレッジを拡張する |
| KMD-116 | Backlog | AI Product | 🧊 アイスボックス（AI 機能・E1 後） | ConfluenceService: 空 href の <a> が storage format で正常にレンダリングされるか実機検証する |
| KMD-140 | Backlog | Viewer / Preview | 📌 残す（carve-out・親完了後） | [carve from KMD-30] README.md を D2 WASM 化に追従させる |
| KMD-141 | Backlog | Misc | 📌 残す（infra・随時） | scripts/wiki/lint_report.sh の自動テスト整備 |
| KMD-142 | Backlog | Misc | 📌 残す（Backlog） | weekly lint 結果の Linear 投稿失敗を observability できるようにする |
| KMD-146 | Backlog | Misc | 📌 残す（infra・随時） | ingest_history.sh の trap EXIT で local 変数参照時に unbound variable |
| KMD-147 | Canceled | Blocked | ❌ 済み取消 | [BLOCKED] ANTHROPIC_API_KEY 未設定で LLM 系 lint / wiki ヘルパが実行不可 |
| KMD-149 | Canceled | Blocked | ❌ 済み取消 | [BLOCKED] ANTHROPIC_API_KEY が ~/.zshrc に未設定 (KMD-145 起因) |
| KMD-156 | Backlog | Misc | 📌 残す（Backlog） | research_create_ticket.md frontmatter description を session-context 前提に書き換え |
| KMD-157 | Backlog | Misc | 📌 残す（Backlog） | ask.sh の出力スキーマ smoke test を追加（## Sources / file marker cite 検証） |
| KMD-158 | Backlog | Pipeline / Infra | 📌 残す（Backlog） | wiki 参照の ask.sh 経由化を 4 subagent 外（kobaamd_update_wiki 等）にも拡張 |
| KMD-159 | Backlog | Pipeline / Infra | 📌 残す（Backlog） | scripts/codex/run.sh の smoke test スクリプトをリポジトリに永続化 |
| KMD-160 | Backlog | Pipeline / Infra | 📌 残す（Backlog） | scripts/codex/run.sh に trap cleanup を追加（一時ファイル残留防止） |
| KMD-161 | Backlog | Pipeline / Infra | 📌 残す（Backlog） | CLAUDE.md の codex exec 例示を scripts/codex/run.sh 経由に書き換え |
| KMD-162 | Backlog | Misc | 📌 残す（Backlog） | existing_blocked_issue の検索を state フィルタ + 件数拡張で堅牢化 |
| KMD-164 | Backlog | Carve-outs | 📌 残す（carve-out・親完了後） | [carve from KMD-122] review_pr Step 5-c 差分検証フローを stub から実装へ |
| KMD-165 | Backlog | Carve-outs | 📌 残す（carve-out・親完了後） | [carve from KMD-122] review_pr 5-a 機械ゲートの fail-open vs fail-closed 設計判断 |
| KMD-166 | Backlog | Pipeline / Infra | 📌 残す（carve-out・親完了後） | [carve from KMD-122] subagent prompts の bash placeholder 規約整備（KMD-XX のリテラル化リスク） |
| KMD-173 | Todo | Knowledge Base [KB] | ▶️ Todo（パイプライン候補） | [KB2-followup] section-context-missing 2 経路の判定差分検証を ANTHROPIC_API_KEY 持参環境で完走 |
| KMD-176 | In Progress | Pipeline / Infra | 🔥 進行中（WIP） | [FOLLOWUP KMD-128] usage 計測機構の堅牢化 (subagent 計装 + 入力 robustness + smoke test) |
| KMD-177 | Backlog | Pipeline / Infra | 📌 残す（Backlog） | subagent MD (create_prd / review_prd) Step 番号リナンバと選択肢 A 整合性整理 |
| KMD-178 | Backlog | Navigation / Sidebar | 📌 残す（Backlog） | TagsViewModel.updateFile を fileToTags 逆引き辞書で O(K) 化 |
| KMD-179 | Backlog | Misc | 📌 残す（Backlog） | タグサイドバー UI/UX 改善（フィルタ動作・HIG・階層タグ・レイアウト） |
| KMD-180 | Backlog | Navigation / Sidebar | 📌 残す（Backlog） | FSEvents 連携でアプリ外ファイル変更をサイドバー集計に反映 |
| KMD-181 | Backlog | Carve-outs | 📌 残す（carve-out・親完了後） | concern-carve-out.md §3 に PR レベル条件 (postmortem-patterns パターン 14) との視点対比を追加 |
| KMD-192 | Backlog | Navigation / Sidebar | 📌 残す（Backlog） | BacklinksViewModel.fileListCache の invalidation 戦略（FSEvents or TTL） |
| KMD-193 | Backlog | Misc | ⏸️ 後（Viewer 磨き込み） | MarkdownService.shellHeadCache のメモリ削減と build race 解消 |
| KMD-195 | Backlog | Pipeline / Infra | 📌 残す（Backlog） | GitHub Actions release runner バージョン固定の定期更新運用を整備 |
| KMD-196 | Backlog | Pipeline / Infra | 📌 残す（infra・随時） | release.yml: GITHUB_OUTPUT 署名値に add-mask を追加（または公開情報である旨を明示） |
| KMD-197 | Backlog | Pipeline / Infra | 📌 残す（infra・随時） | release.yml: appcast rollback push 失敗時の silent failure を警告出力に改善 |
| KMD-198 | Backlog | Pipeline / Infra | 📌 残す（infra・随時） | release.yml: Validate secrets ステップに SU_PUBLIC_ED_KEY の空文字/PLACEHOLDER 検証を追加 |
| KMD-199 | Backlog | Pipeline / Infra | 📌 残す（infra・随時） | release.yml: sign_update バイナリ選択を決定的なパスで固定（-p フラグ追加も含む） |
| KMD-201 | Canceled | Pipeline / Infra | ❌ 済み取消 | [BLOCKED] Codex quota / rate-limit detected |
| KMD-204 | Canceled | Pipeline / Infra | ❌ Duplicate（KMD-201 と同一 BLOCKED） | [BLOCKED] Codex quota / rate-limit detected |
| KMD-205 | Backlog | Carve-outs | 📌 残す（carve-out・親完了後） | KMD-117 carve-out: LT 資料を docs/talks/ から適切な場所に分離 |
| KMD-206 | Backlog | Pipeline / Infra | 📌 残す（carve-out・親完了後） | KMD-117 carve-out: autopilot.sh の CODEX_EXEC_SANDBOX=danger-full-access デフォルト化のリ |
| KMD-207 | Backlog | Pipeline / Infra | 📌 残す（carve-out・親完了後） | KMD-117 carve-out: run_bundle.sh の Slack 通知 JSON インジェクション修正 |
| KMD-208 | Backlog | Pipeline / Infra | 📌 残す（carve-out・親完了後） | KMD-117 carve-out: scripts/usage/report.sh と retro.sh に smoke test を追加 |
| KMD-209 | Backlog | Misc | 📌 残す（Backlog） | ask.sh を Gemini 対応に切り替え（全呼び出し側の更新込み） |
| KMD-210 | Backlog | AI Agent Ports | 🧊 アイスボックス（競合調査・E1 後） | Add project-scoped writing rules via .kobaamd/rules.md (Cursor .cursor/rules por |
| KMD-211 | Backlog | AI Agent Ports | 🧊 アイスボックス（競合調査・E1 後） | Add @-mention context picker for AI chat and inline edit (Cursor @-mention port) |
| KMD-212 | Backlog | AI Agent Ports | 🧊 アイスボックス（競合調査・E1 後） | Adopt Zed ACP (Agent Client Protocol) as a pluggable AI provider layer |
| KMD-213 | Backlog | AI Agent Ports | 🧊 アイスボックス（競合調査・E1 後） | Add background reviewer agent for semantic Markdown linting (Cursor Background A |
| KMD-214 | Backlog | AI Agent Ports | 🧊 アイスボックス（競合調査・E1 後） | Add inline diff Accept/Reject UI for AI rewrites (Zed Edit Predictions / Cursor  |
| KMD-215 | Backlog | Pipeline / Infra | 📌 残す（infra・随時） | run_bundle.sh: truncate Codex payloads for pipeline_active/daily |
| KMD-216 | Canceled | Misc | ❌ 取消（空 GH payload） | [GH sync bug] empty GitHub payload |
| KMD-217 | Backlog | E1 Re-concept | ▶️ E1 継続 | [Re-concept Epic] E1 二段レール: Terminal + Knowledge Viewer |
| KMD-218 | Reviewed | E1 Re-concept | ✅ 実装済・マージ待ち | [RC-P0] PRD + ADR: E1 レイアウト・セッションモデル・既存機能の配置 |
| KMD-219 | Done | E1 Re-concept | ✅ 完了（アーカイブ待ち） | [RC-P0] Spike: 埋め込みターミナル実装方式（PTY / SwiftTerm / Sandbox） |
| KMD-220 | Reviewed | E1 Re-concept | ✅ 実装済・マージ待ち | [RC-P1] Slice: E1 3ペインシェル（左レール / 中央 / 右）プレースホルダ |
| KMD-221 | Reviewed | E1 Re-concept | ✅ 実装済・マージ待ち | [RC-P1] Slice: Session モデル + git worktree 一覧 |
| KMD-222 | Reviewed | E1 Re-concept | ✅ 実装済・マージ待ち | [RC-P1] Slice: 左レール上段 — Session リスト UI |
| KMD-223 | Reviewed | E1 Re-concept | ✅ 実装済・マージ待ち | [RC-P2] Slice: File tree を active worktree にスコープ |
| KMD-224 | Reviewed | E1 Re-concept | ✅ 実装済・マージ待ち | [RC-P2] Slice: セッション切替オーケストレーション（tree + editor + viewer） |
| KMD-225 | Done | E1 Re-concept | ✅ 完了（アーカイブ待ち） | [RC-P3] Slice: 中央ペイン — 埋め込みターミナル MVP（単一セッション） |
| KMD-226 | Done | E1 Re-concept | ✅ 完了（アーカイブ待ち） | [RC-P3] Slice: セッションごとの PTY ライフサイクル |
| KMD-227 | Done | E1 Re-concept | ✅ 完了（アーカイブ待ち） | [RC-P4] Slice: 右ペイン Viewer タブ（md / D2 / diff / csv） |
| KMD-228 | Done | E1 Re-concept | ✅ 完了（アーカイブ待ち） | [RC-P4] Slice: 成果物出現フロー（NEW バッジ + 自動オープン） |
| KMD-229 | Backlog | E1 Re-concept | ▶️ 次（P2 並行可） | [E1-P2] Quick Open を active session スコープに制限 |
| KMD-230 | Backlog | E1 Re-concept | ⏸️ 後（P3+） | [RC-P5] Slice: Outline / Backlinks / Tags / AI Chat の E1 配置 |
| KMD-231 | Reviewed | E1 Re-concept | ✅ 実装済・マージ待ち | [RC-P5] Slice: 旧 Markdown 3ペイン UI の feature flag 共存 |
| KMD-232 | Backlog | E1 Re-concept | ▶️ 次（P2 並行可） | [RC-P6] E2E: セッション切替 smoke（Tart VM） |
| KMD-233 | Backlog | E1 Re-concept | ⏸️ 後（P3+） | [RC-P6] Docs: README / wiki を E1 前提に更新 |
| KMD-234 | Todo | E1 Re-concept | 🔥 今すぐ（P2）※プロジェクト未紐付 | [E1-P2] PRD: Terminal × Editor × Preview 共存 UX |
| KMD-235 | Backlog | E1 Re-concept | ▶️ E1 子チケット（プロジェクト紐付推奨） | [E1-P2] 右ペイン Source\|Rendered 同時表示 Split |
| KMD-236 | Backlog | E1 Re-concept | ▶️ E1 子チケット（プロジェクト紐付推奨） | [E1-P2] フォーカスルーティングとショートカット（Terminal / Viewer / Files） |
| KMD-237 | Backlog | E1 Re-concept | ▶️ E1 子チケット（プロジェクト紐付推奨） | [E1-P2] 拡張子別デフォルト Viewer レイアウト |
| KMD-238 | Todo | E1 Re-concept | 🔥 今すぐ（P2）※プロジェクト未紐付 | [E1-P2] merge feature/e1-reconcept-shell → main |
| KMD-239 | Backlog | E1 Re-concept | ▶️ E1 子チケット（プロジェクト紐付推奨） | [E1-P3] git worktree セッション（Settings から復活） |
