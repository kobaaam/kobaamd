# Codex 引き継ぎ資料 — kobaamd

最終更新: 2026-05-15 / 引き継ぎ元: Claude Opus（メイン）
対象読者: 本リポジトリのオーケストレータ役を引き継ぐ Codex セッション

このドキュメントは「Codex が追加調査を最小限にして自律的に開発・検証・次タスク判断を継続できる」ことを目的とする。
推測と事実の区別が必要な箇所には `[推測]` を付与。

> **⚡ 最優先で読むファイル**: 本ハンドオフより先に [`AGENTS.md`](../AGENTS.md)（同内容を [`agent.md`](../agent.md) にも複製）を必ず読むこと。  
> `CLAUDE.md` は `AGENTS.md` への redirect スタブに置き換わっており、Codex セッションでは **`AGENTS.md` 冒頭の「Codex 優先ルール」が他の運用ルールに優先する**。本ハンドオフは AGENTS.md の "Claude Code からの移管情報" を運用観点で補完するためのドキュメントである。
>
> **⚠️ AGENTS.md「Claude Code からの移管情報」セクション内のコマンド例（`source ~/.zshrc` 直呼び・`curl` URL に `$GEMINI_API_KEY` を載せる Gemini 呼び出し例など）は Claude Code セッション向けの履歴資料**。Codex セッションでは **本書 §4 の安全な代替手順（限定 env 読み込み・値非表示確認）を優先**すること。AGENTS.md の旧コマンドをそのまま再現すると、Codex の sandbox で alias 副作用やキー漏洩を起こす恐れがある。

---

## 1. プロジェクト概要

### 目的（事実）
- **kobaamd** = Mac ネイティブの軽量 Markdown エディタ（個人 OSS）。
- ビジョン: 「AI が生成した Markdown を、Mac で最も快適に扱えるエディタ」。
- 同時に「**AI エージェント群が自律的に開発を進めるパイプラインの実験場**」も兼ねている（`AGENTS.md`「Claude Code からの移管情報」セクション参照）。
- ライセンス: 本リポジトリの `LICENSE`。

### アプリ本体
- 単一 SPM 実行ターゲット `kobaamd`（`Package.swift` 参照）。
- macOS 14+ / arm64 推奨。
- SwiftUI + AppKit（`NSTextView` ラップ）構成、`@Observable` ベースの MVVM。
- 外部依存: `swift-markdown`（Apple）/ `Sparkle` 2.9+ / `swift-tree-sitter` / `tree-sitter-markdown`（`Package.resolved`）。

### 主要ディレクトリ
| パス | 役割 |
|---|---|
| `Sources/App/` | エントリポイント・`AppViewModel`・`AppCommand`・`AppVersion` |
| `Sources/Models/` | `EditorTab` / `FileNode` / `Frontmatter` / `Backlink` 等のドメインモデル |
| `Sources/Services/` | `FileService` / `AIService` / `MarkdownService` / `WikiIndexService` / `BacklinksScanner` 等の副作用層 |
| `Sources/ViewModels/` | 各画面の VM（`AIChatViewModel` / `OutlineViewModel` / `BacklinksViewModel` 等） |
| `Sources/Views/` | SwiftUI ビュー群（`MainWindowView` ハブ + サブディレクトリ別） |
| `Sources/CLI/` | kobaamd バイナリの second face: `kobaamd mcp <vault>` stdio MCP server 実装一式（`MCPEntryPoint` / `MCPProtocol` / `MCPServer` / `VaultPath` / `WikiSearchIndex` / `Tools/`、KMD-69 で追加） |
| `Sources/Diagnostics/` | 計測・ログユーティリティ |
| `Sources/Resources/` | バンドル resources（JS / icon 等） |
| `Tests/kobaamdTests/` | Swift Testing (`@Suite`/`@Test`) のユニットテスト（30 ファイル） |
| `E2ETests/kobaamdE2ETests/` | XCUITest ベース E2E（Tart VM 経由で実行） |
| `docs/` | PRD / ADR / learnings / wiki / changelog / minutes / talks |
| `docs/wiki/articles/` | LLM Wiki（subagent が一次資料として参照） |
| `scripts/` | post-build / launchd / linear / wiki / hooks / codex / recovery |
| `.claude/agents/` | **Claude Code 用** subagent 定義（14 ファイル）。Codex は **仕様・運用参考資料**として読むこと。Codex のツール体系では `claude -p --agent ...` 経由の直接実行は不可なので、必要な処理は Codex の subagent 呼び出しに読み替える |
| `.claude/commands/` | **Claude Code 用** slash command 定義（28 ファイル）。`/kobaamd_*` 形式の slash は Claude Code セッションでしか動かない。Codex は当該 `.md` の手順を読んで、対応する素の shell コマンド / `lq.sh` / `gh` 呼び出しに翻訳して実行する |
| `.logs/` | パイプライン実行ログ・Linear write 監査・state snapshot（gitignore） |

### 技術
- 言語: Swift 5.9（`swift-tools-version`）。実機 toolchain は `Apple Swift 6.3.2`（Command Line Tools）。
- ビルド: Swift Package Manager（Xcode プロジェクトなし）。
- パーサー: `swift-markdown` + TreeSitter（markdown grammar）。
- プレビュー: `WKWebView` + bundled EasyMDE / Mermaid.js（オフライン優先）。
- 自動更新: Sparkle 2.x（EdDSA 署名）。
- テスト: Swift Testing（XCTest ではない）。

---

## 2. 現在の作業状況

### 直近の主目的（事実）
- **KMD-182**: DMG ビルド + 署名 + GitHub Release を GitHub Actions で自動化（マージ済み: `c5dcd1c`）。
- **KMD-169**: subagent doc / wiki の allowlist 限界を正確な降格表現に修正（マージ済み: `fab9280`、タイトルに `[WIP]` が残るが PR 自体は merged）。
- 上記 2 件のリリース後、フロー上は「Linear `In Progress` / `in Review` / `Human in Review` が 0 件」の落ち着いた状態。
- 直近の `KMD-194`（pipeline_active preflight）/ `KMD-191`（エディタ scroll 改善）/ `KMD-187`（APIKeyStore キャッシュ）も merged 済み。

### 完了済みの主な変更（直近 1 週間）
| Issue | 内容 | コミット |
|---|---|---|
| KMD-169 | allowlist 限界の表現修正 | fab9280 |
| KMD-182 | DMG + 署名 + GitHub Release CI 化 | c5dcd1c |
| KMD-194 | pipeline_active 起動前 preflight + 金曜 07:00 自動再開 | f145053 |
| KMD-191 | エディタの scroll / ファイル切替体感改善（5 レイヤー） | 5e80a3e |
| KMD-187 | APIKeyStore に in-process cache | 6f8cfd4 |
| KMD-184 | md scroll 中の loading 頻発解消 | b03a17f |

### 未完了の変更（事実、2026-05-15 引き継ぎ作成時点）

> ⚠️ Linear / Git / PR 状態は時間で変わる。Codex は判断前に必ず `git status --short --ignored` / `./scripts/linear/lq.sh issue.list ...` / `gh pr list --state open` を**再実行**して最新値で判断すること。本セクションは snapshot に過ぎない。

`git status --short --ignored` 実測:

```
?? AGENTS.md
?? agent.md
?? docs/ai-handoff.md
?? docs/talks/
?? "\343\202\242\343\202\246\343\203\210\343\203\251\343\202\244\343\203\263.md"
!! .DS_Store
!! .build/
!! .cache/
!! .claude/.DS_Store
!! .claude/settings.local.json
!! .logs/
!! CLAUDE.md
!! dist/
...
```

- **modified 行はゼロ**（tracked ファイル変更なし）。
- ただし `CLAUDE.md` が `!!`（gitignored）に分類されている — **`.gitignore` に `CLAUDE.md` が含まれている**ため、現在の redirect スタブ書き換えは git tracked ではない（手元のローカル変更）。`git ls-files CLAUDE.md` は空。
- **新規 untracked ファイル**:
  - `AGENTS.md` / `agent.md` — **Codex の一次資料**として新設。本ハンドオフと同じセッションで生成された可能性が高い `[推測]`。次回コミットで含めるかは人間判断。
  - `docs/ai-handoff.md` — **本ファイル**。
  - `docs/talks/` — LT 発表資料一式（`lt-ai-pipeline-outline.md` / `lt-presentation.pptx` / `lt-presentation.pdf` / `lt-presentation-skeleton.pptx` / `lt-presentation-skeleton.pdf`）。社内 LT 用、コードベースとは独立した個人成果物。
  - `アウトライン.md`（ルート） — 上記 LT スライドの作業中アウトライン。pptx 化済み。

> Codex の扱い方:
> - `AGENTS.md` / `agent.md` / `docs/ai-handoff.md` は **ハンドオフ自体の成果物**なので、Codex が最初に動くタイミングで人間に「これを 1 つの PR にまとめてコミットしてよいか」を確認するのが現実的。
> - `docs/talks/` と `アウトライン.md` は LT 終了まで個人保持の方針 `[推測]`。**Codex 側で勝手に削除・移動しない**こと。

### 途中で止めた理由 / 懸念点
- 上記 LT 資料は「発表が終わるまで個人作業として保持」が妥当（`[推測]` だが LT は社内勉強会の準備物で本リポの開発タスクではないため）。
- パイプライン側に未完了タスクは溜まっていない（in progress = 0）。

### 作業中ブランチ / 関連 PR
- 現在のブランチ: `main`（リモートと同期、untracked のみ）。
- 開いている PR は **すべて postmortem 系**（人間レビュー待ち、コード変更には影響しない）:
  - #112 postmortem(KMD-182)
  - #103 postmortem(KMD-68)
  - #100 postmortem(KMD-66)
  - #97 postmortem(KMD-128)
  - #94 postmortem(KMD-133)
  - #92 postmortem(KMD-131)
  - #90 postmortem(KMD-155)
  - #88 postmortem(KMD-154)
  - ブランチ命名は `feature/learnings-KMD-XX`。本体には影響しない docs 追加。

### 関連 Issue（Linear KMD team の現状サマリ）

> ⚠️ 数字は 2026-05-15 時点の snapshot。**Codex は判断前に必ず `./scripts/linear/lq.sh issue.list --team KMD --state <state>` で再取得**すること。

- `In Progress` / `in Review` / `Human in Review` / `Reviewed`: **0 件**（クリーンな状態）。
- `Todo`: 14+ 件（うち多くは `[carve from KMD-XXX]` の改善 carve-out）。次に着手するなら `kobaamd_assign_work` または `kobaamd_pipeline_active` 起動。
- `Backlog`: 多数。直近で KMD-195〜199 が release.yml のセキュリティ磨き込みとして起票済み。

---

## 3. Codex が最初に見るべきファイル

| パス | 見る理由 | 関連シンボル / 設定 |
|---|---|---|
| `AGENTS.md` / `agent.md` | **最優先一次資料**。Codex 優先ルール / モデル割り当て / token 圧縮戦略 / 「Claude Code からの移管情報」（元 CLAUDE.md 本体） | 「Codex 優先ルール」「Codex モデル割り当て」 |
| `CLAUDE.md` | **ローカルには AGENTS.md への redirect スタブが存在するが、`.gitignore` 対象でコミット不可**。fresh clone には存在しない可能性が高い。一次資料は `AGENTS.md` / `agent.md` を見ること | — |
| `docs/wiki/articles/` | LLM Wiki 一次資料。`scripts/wiki/load_all.sh` で全体投入できる | 各記事の frontmatter `wiki_value` |
| `Package.swift` | 依存・ターゲット構成。実行可能ターゲットは `kobaamd` のみ | dependencies / unsafeFlags |
| `Sources/App/kobaamdApp.swift` | アプリエントリポイント・WindowGroup 構成 | `@main` |
| `Sources/App/AppViewModel.swift` | 全 VM の hub。タブ・ファイル状態を統括 | `openInTab()` 等 |
| `Sources/Views/MainWindowView.swift` | UI 構成のハブ | サイドバー・エディタ・プレビュー配置 |
| `Sources/Services/FileService.swift` | ファイル I/O の中核 | `supportedExtensions` |
| `Sources/Services/AIService.swift` | OpenAI / Anthropic / Gemini 連携 | API key は `APIKeyStore` 経由 |
| `Sources/Services/APIKeyStore.swift` | Keychain 経由の API キー管理 + in-process cache（KMD-187） | `cache` プロパティ |
| `Sources/CLI/MCPServer.swift` | kobaamd バイナリの **second face**: `kobaamd mcp <vault>` で stdio MCP server を起動。Claude Desktop / Cursor から vault を読ませる用途（KMD-69） | `MCPEntryPoint` / `WikiSearchIndex` |
| `docs/mcp-setup.md` | 上記 MCP server の Claude Desktop / Cursor 接続手順 | `mcpServers` JSON |
| `scripts/usage/check.sh` | API 利用量の窓集計（最近 N 時間）。閾値超過で exit 10。subagent 起動前のコストガード（KMD-128） | `.logs/api_usage.jsonl` |
| `scripts/recovery/recover_halted.sh` | `In Progress` で詰まった issue を実装 / マージへリカバリ。launchd から定期実行中 | `.logs/halted_recovery.log` |
| `scripts/post-build.sh` | `.app` バンドル作成 + Sparkle 公開鍵注入 + codesign | 環境変数 `KOBAAMD_SU_PUBLIC_ED_KEY` |
| `scripts/linear/lq.sh` | Linear I/O 単一エントリ（MCP は撤去済み） | `issue.get` / `issue.update` / `issue.transition` / `comment.add` |
| `scripts/wiki/ask.sh` | wiki 全文を Prompt Cache に乗せる subagent ヘルパー | `cache_control: ephemeral` |
| `scripts/launchd/run_bundle.sh` | 定期実行の launchd エントリ | `pipeline_active` / `daily` / `weekly` |
| `.claude/agents/kobaamd_*.md` | 14 subagent 定義（PRD 作成・実装・レビュー・マージ・wiki 更新）。**Claude Code 専用、Codex は仕様参照のみ**（直接実行不可、自前 subagent 体系に翻訳して使う） | front matter `model:` |
| `.claude/commands/kobaamd_pipeline_active.md` | 30 分間隔の中核パイプライン定義。**Claude Code 専用、Codex は仕様参照のみ** | フェーズ A / B 構成 |
| `.github/workflows/release.yml` | DMG ビルド + GitHub Release CI（KMD-182） | secrets: `SU_PUBLIC_ED_KEY` / `SPARKLE_EDDSA_PRIVATE_KEY` |
| `.logs/pipeline_state.json` | Linear 全 issue スナップショット（読み取り専用、自動生成） | `kobaamd_snapshot_state` が更新 |

---

## 4. 実行コマンド

### セットアップ（初回のみ）
```bash
# git hooks（pre-commit のシークレット検知 / pre-push の main 直 push ブロック）
./scripts/hooks/install.sh

# API キー（LINEAR / OPENAI / GEMINI / ANTHROPIC）は ~/.zshrc に既設定（事実）。
# Codex sandbox では source ~/.zshrc が alias や function を読み込んで
# 後続コマンド引数を壊した過去事例あり。以下のいずれかで副作用と値リークを抑える:

# (A) 存在確認のみ（値は出力しない — env | rg だと値が漏れるので必ず key 名のみで grep）
env | cut -d= -f1 | rg -i '^(LINEAR_API_KEY|OPENAI_API_KEY|GEMINI_API_KEY|ANTHROPIC_API_KEY)$'

# (B) 個別キーの存在チェック（値を stdout に流さない）
printenv LINEAR_API_KEY >/dev/null && echo "LINEAR_API_KEY: set" || echo "LINEAR_API_KEY: MISSING"

# (C) 必要キーだけ scope を絞って読む（alias 副作用を避ける）
export LINEAR_API_KEY="$(zsh -lic 'printf %s "$LINEAR_API_KEY"')"

# (D) どうしても source が必要なら subshell に閉じ込めて、外側に副作用を出さない:
( set +u; source ~/.zshrc && ./scripts/linear/lq.sh ... )
```

### 開発ビルド + バンドル化（検証済み: `swift build` は 2.89s で成功）

**Codex sandbox では `open .build/kobaamd.app` の GUI 起動はユーザー承認 / 人間動作確認の段階**。ビルド・バンドルまでは自動、起動は別ステップに分ける:

```bash
# Step 1: ビルド + バンドル化（Codex が自動で OK）
swift build && ./scripts/post-build.sh

# Step 2: GUI 起動（人間または明示承認が必要）
open .build/kobaamd.app
```

### リリースビルド
```bash
# Step 1: ビルドのみ自動可
swift build -c release
./scripts/post-build.sh release

# Step 2: GUI 起動は人間確認
open .build/kobaamd.app
```

### テスト
```bash
swift test 2>&1 | tee /tmp/test.log
```

> **⚠️ 検証ギャップ（事実 + リスク）**: 本セッションでの実行では `swift test` が `Build complete!` のみ出力し、各 `@Suite` の結果行が表示されずに exit 0 で終了した（`/tmp/test.log` 3 行）。  
> 原因 `[推測]`: Command Line Tools の SDK が macosx26 系 / Package.swift 側は macOS 14 ターゲット指定、かつ `Tests/kobaamdTests` は Swift Testing (`@Suite`/`@Test`) のみで XCTest 旧 runner を経由しないため、SwiftPM のテストランナーが探索に失敗している可能性が高い。
>
> **⚠️ ⚠️ これは「テスト pass」ではなく「テスト no-op」の可能性が高い。exit 0 を素直に受け入れると静かに壊れたコードを merge する**。Codex が PR を出すときは Test plan に必ず以下を明記すること:
> - `swift test` は exit 0 になるが Swift Testing の結果行が出ない既知ギャップがあること
> - 機能検証は最低限の手動 GUI チェックまたは `./scripts/run_e2e_tests.sh`（Tart VM 必要）で代替したこと
> - 触ったロジックに対応する `Tests/kobaamdTests/*.swift` がある場合、xcodebuild または将来の修正で再走させる前提で記録を残すこと
>
> **対処の選択肢**:
> - `xcodebuild test -scheme kobaamd -destination 'platform=macOS,arch=arm64'`（フル Xcode が入っている場合）
> - Tart VM の E2E ランナー `./scripts/run_e2e_tests.sh`
> - `kobaamd_validate_build` subagent の手順では `swift test 2>&1 | tee /tmp/test.log` をそのまま使っているので、**従来通り build 成功までを最低限のゲートとして扱い、機能テストは E2E に寄せる**運用が現実的。
>
> Codex 側で本件を深掘りするなら、別 Issue として `[infra] swift test が Swift Testing 結果を出力しない原因調査` を起票する。

### Lint / Format
```bash
# Claude Code セッションでは slash command を使う:
#   /kobaamd_format_code
# Codex セッションでは slash は呼べないので、.claude/commands/kobaamd_format_code.md を
# 読んで対応する素のコマンドに翻訳する。典型的には:
brew install swift-format            # 未インストールの場合
swift-format format -i -r Sources/   # 一括フォーマット（実コマンドはコマンド定義を要確認）
swift-format lint -r Sources/        # lint
```

> **⚠️ 注意**: `swift-format` は PATH に **未インストール**（事実、`which swift-format` で確認）。
> CI / hooks で自動 lint は走っていない。実行前に `brew install swift-format` か `xcrun --find swift-format` で導入する必要がある。導入は依存追加に当たるので **人間承認推奨**。

### 型チェック
- `swift build` が型チェックを兼ねる（Swift の通常運用）。専用の型チェック single-shot は不要。

### 既知の失敗するコマンド
| コマンド | 失敗の理由 |
|---|---|
| `swift test`（結果出力）  | 上記の通り Swift Testing が SwiftPM ランナー側で discover されていない可能性。`Build complete!` のみで結果が出ない。 |
| `swift-format` 直接呼び出し | バイナリ未インストール。 |
| `git push origin main` | pre-push hook で **ブロック済み**。feature branch + PR が必須。 |

---

## 5. アーキテクチャ上の重要な判断

### 採用済みの設計判断
1. **MVVM + `@Observable`**: `Sources/ViewModels/` に各画面の VM を置く。Service は Service 層に閉じる。
2. **`NSTextView` ラップ**: `SwiftUI.TextEditor` ではなく `NSTextView` を `NSViewRepresentable` でラップしている。macOS 26 で文字不可視バグの実績があるため要注意（`AGENTS.md` 移管情報セクション + ユーザー auto-memory `feedback_nstextview_macos26.md` 参照）。
3. **Markdown パーサーは `swift-markdown` (Apple)**: 自前構文解析や別 OSS への置換は避ける（Phase 4 で TreeSitter 強化予定）。
4. **WKWebView + bundled JS**: Mermaid.js / EasyMDE は CDN ではなく `Sources/Resources/` にバンドル（オフライン優先）。
5. **API キーは Keychain + in-process キャッシュ**: `APIKeyStore`（KMD-187 で cache 追加）。`UserDefaults` に書かない。
6. **Sparkle EdDSA 公開鍵は post-build 注入**: `Info.plist` への直書き禁止（コミット履歴に鍵を残さない）。`scripts/post-build.sh` で `$KOBAAMD_SU_PUBLIC_ED_KEY` から注入。順序「Info.plist 上書き → 公開鍵注入 → codesign」を変えない。
7. **Linear I/O は `scripts/linear/lq.sh` 一本**: hosted MCP（`mcp__linear__*`）は撤去済み。`.mcp.json` は git 管理外（ファイル自体は残るがコミット対象外、`AGENTS.md`「Linear I/O ポリシー」参照）。
8. **wiki 参照は Prompt Caching 方式 (Phase 1)**: `scripts/wiki/ask.sh` 経由。検索層は 20 万 token を超えるまで導入しない。
9. **subagent モデル割り当て**: 標準は **Sonnet**、Opus は誤判定の代償が大きい / 創造性必要 / 低頻度（review_security・research_create_ticket・improve_prompt）に限る。Haiku はバッチ判定（section-context-check）。**これは Claude Code セッション専用の割り当て**。**Codex セッションでは AGENTS.md 冒頭「Codex モデル割り当て」（Orchestrator=gpt-5.5 / Worker=gpt-5.4 / Explorer・Verifier・Batch=gpt-5.4-mini）に読み替える**。
10. **パイプラインフロー**: `draft → backlog → todo → In Progress → in Review →（必要なら Human in Review）→ Reviewed → Done`。**concern=0 かつ非 `[BREAKING]` は Human を通さず自動マージ**。

### 避けるべき実装方針
- **AGENTS.md 移行前の役割分担を Codex セッションに機械適用すること**: 旧 CLAUDE.md の「Claude が `.swift` を書くな」ルールは Claude セッション向け。Codex は **本来の実装者**なので、Codex が `.swift` を書くこと自体は正常運用。ただし AGENTS.md の Codex 優先ルールに従い、独立調査・限定実装は subagent（Worker / Explorer）へ委譲して親 context を温存する。
- `Info.plist` に Sparkle 公開鍵を直書きする変更。
- `Process()` を新たに導入する変更（KMD-30 / KMD-31 で削減方針、`docs/wiki/articles/practices/security-hardening.md`）。
- `main` への直接 push（pre-push hook でブロック）。
- 1 PR に複数の無関係変更を混ぜる（PR ルール）。
- `mcp__linear__*` / `.mcp.json` への再依存（撤去済み）。
- 任意の subagent に `tools: [..., mcp__linear__*]` を再宣言する。

### 既存のローカル規約
- ブランチ: `feature/<KMD-XX>-<slug>`。
- コミット: タイトルに `KMD-XX:` プレフィックス。
  - **Co-authored-by の方針**（Codex 引き継ぎ後）:
    - **Codex セッションの正式な co-author 表記は未確認**。人間（kobaaam）に確認するまでは **co-author を付けない**運用にする。確認後にプロジェクト規約として `AGENTS.md` または本ハンドオフに追記する。
    - 旧 Claude セッションが書いた既存コミットは `Co-Authored-By: Claude Opus ...` 形式で残っているが、**Codex 側で過去コミットを書き換えない**（履歴の retro-write 禁止）。
    - 人間が直接書いたコミットには co-author を付けない（従来通り）。
- 命名: kobaamd 専用の subagent / slash は `kobaamd_<verb>_<output>` 形式統一。
- PRD: `docs/prd/<KMD-XX>-<slug>.md` テンプレート。Section 11「Gemini 調査ログ」に生プロンプト + 生回答を記録するが、**記録前に secrets / API キー / access token / 個人情報（メールアドレス・氏名等）を redact** すること（PRD は OSS リポジトリにコミットされるため永続化リスクが高い）。秘密情報を含む調査結果は別途 `.logs/`（gitignored）に置き、PRD には要旨だけを残す。
- Wiki 記事: `docs/wiki/SCHEMA.md` 準拠 + `wiki_value` 判定（`high/medium/low`）で ingest gating。
- ログ: `.logs/` 配下（gitignore）。Linear write は `linear_writes.jsonl` に自動記録される（`lq.sh` 経由のみ）。

### 変更時に壊れやすい境界
- `scripts/post-build.sh` のステップ順序（特に Sparkle / Hardened Runtime）。
- `Package.swift` の `unsafeFlags` — Command Line Tools の Testing framework rpath をハードコードしている。Xcode / CLT のアップデートで影響を受けやすい。
- `NSTextView` ラッパー周辺（macOS 26 不可視バグ実績）。テキスト描画 / レイアウトの変更は `feedback_nstextview_macos26.md` の memory に従う。
- `scripts/linear/lq.sh` の payload 形式（write 失敗時に `.logs/linear_writes.jsonl` を汚す）。
- launchd plist の `StartCalendarInterval` 形式（KMD-194 で resume 追加）。
- `WKWebView` 経由の XSS surface（KMD-28 検討中）。

---

## 6. 未解決タスク

優先度は Linear priority に基づく（1=Urgent, 4=Low）。詳細は Linear 各 issue を参照。

### 優先度高（Todo / priority 3 以上）
| ID | 目的 | 変更対象（推定） | 期待挙動 | 検証 | リスク | 優先度 |
|---|---|---|---|---|---|---|
| KMD-183 | 開発時の Keychain ACL を `partition-list` で安定化（Developer ID 不要） | `scripts/` / dev セットアップ手順 | dev ビルドでも Sparkle 関連が Keychain prompt 連発しない | 手動: kobaamd 起動 → API キー保存 → 再起動して再 prompt が出ないこと | Keychain 操作ミスで既存 dev 環境を破壊しうる | P3 |

### 優先度中〜低（Todo / priority 4）— carve-out 群が中心
| ID | 目的 | 変更対象（推定） | 検証 | リスク |
|---|---|---|---|---|
| KMD-190 | runtime ログで `securityd:dbsession` 削減を経験的検証（KMD-187 carve） | runtime log 取得 + 解析 | log diff | データ不足 |
| KMD-189 | APIKeyStore キャッシュテストに `SecItemCopyMatching` 呼び出し回数の spy 検証追加 | `Tests/kobaamdTests/APIKeyStoreCacheTests.swift` | swift test | テスト二重実装 |
| KMD-188 | APIKeyStore legacy migration の cache 二重書き込みクリーンアップ | `Sources/Services/APIKeyStore.swift` | unit test + 手動 | migration 後のキー消失 |
| KMD-186 | `NSTextViewWrapper` の `MainActor.assumeIsolated` 二重ネスト解消 | `Sources/Views/Editor/` | build + UI 手動 | UI 描画タイミング変化 |
| KMD-185 | MarkdownWebView Coordinator throttle のユニットテスト追加 | `Tests/kobaamdTests/ScrollSyncThrottleTests.swift` | swift test | timing-dependent flake |
| KMD-173 | section-context-missing 2 経路の判定差分検証（`ANTHROPIC_API_KEY` 環境で完走） | `scripts/wiki/lib/section-context-check.sh` | wiki lint | API 課金発生 |
| KMD-172 | `claude -p` の variadic option 後置を CI で検出する CLI 引数 lint | scripts / CI | dry-run | CI 過敏で偽陽性 |

### Phase 4 ロードマップの現在地（CLAUDE.md / AGENTS.md 「現在のフェーズ」と差分あり）
AGENTS.md は **Phase 3 完了 / Phase 4 = TreeSitter / アウトライン / PDF Export** と記載しているが、実コードでは:
- **TreeSitter**: `Sources/Services/TreeSitterHighlightService.swift` 実装済み（移行は段階的、`HighlightService` と並走）
- **アウトライン**: `Sources/ViewModels/OutlineViewModel.swift` + Outline ペイン実装済み
- **PDF Export**: `Sources/Views/MainWindowView.swift` / `Sources/App/AppCommand.swift` 等に **PDF 関連コードあり**（`rg -l 'pdf|PDFExport|exportPDF' Sources/` でヒット 7 ファイル）。実装は進行している `[推測]`

結論として **Phase 4 は事実上ほぼ完了**しており、AGENTS.md の「Phase 4（次）」表現は **`[推測]` 古い**。Codex がフェーズ宣言を更新するなら別 issue を立てて人間に判断を仰ぐこと。

### Backlog（直近起票、release.yml 周辺）
KMD-195〜199 はすべて `c5dcd1c`（KMD-182 リリース CI）からの carve-out で release.yml のセキュリティ磨き込み:
- KMD-199: `sign_update` バイナリ選択を決定的なパスで固定
- KMD-198: Validate secrets ステップに `SU_PUBLIC_ED_KEY` の空文字 / PLACEHOLDER 検証追加
- KMD-197: appcast rollback push 失敗時の silent failure を警告出力に改善
- KMD-196: `GITHUB_OUTPUT` 署名値に `add-mask` 追加（または公開情報明示）
- KMD-195: GitHub Actions release runner バージョン固定の定期更新運用整備

詳細は `./scripts/linear/lq.sh issue.get KMD-XX` で取得可能。

---

## 7. 環境・秘密情報

### 必要な環境変数（用途のみ、値は記載しない）
| 変数 | 用途 | 設定場所 |
|---|---|---|
| `LINEAR_API_KEY` | Linear API（`lq.sh` Bearer 認証） | `~/.zshrc`（個人環境） |
| `OPENAI_API_KEY` | Codex CLI / 直 API | `~/.zshrc` |
| `GEMINI_API_KEY` | Gemini 調査 | `~/.zshrc` |
| `ANTHROPIC_API_KEY` | `scripts/wiki/ask.sh` の wiki Q&A | `~/.zshrc` |
| `KOBAAMD_SU_PUBLIC_ED_KEY` | Sparkle 公開鍵注入（post-build 時のみ） | リリース時は GitHub Secret、ローカル開発は **未設定でも debug ビルドは動く** |
| `SPARKLE_EDDSA_PRIVATE_KEY` | リリース appcast 署名 | GitHub Secret（リポジトリ secret） |
| `GH_TOKEN` | GitHub Actions / ローカル `gh` CLI | GitHub Secret / `gh auth login` |

### ローカル CLI ツールチェイン（事実、すべて 2026-05-15 時点で検証済み）
| ツール | パス | 状態 | 用途 |
|---|---|---|---|
| `gh` | `/opt/homebrew/bin/gh` | ✅ 認証済（account `kobaaam`、active true） | PR / Actions 操作 |
| `jq` | `/usr/bin/jq` | ✅ 存在 | `lq.sh` 等の JSON 整形 |
| `tart` | `/opt/homebrew/bin/tart` | ✅ 存在 | E2E 用 VM ランナー |
| `swift` | CLT 6.3.2 | ✅ 存在 | ビルド / テスト |
| `swift-format` | — | ❌ 未インストール | `/kobaamd_format_code` 走らせる前に要導入 |
| `xcrun` | CLT | ✅ 存在 | 各種 Apple toolchain wrap |
| `launchctl` | system | ✅ `pipeline_active` PID 27804 で稼働中 / daily, weekly ロード済（待機中） | 定期実行 |

### 外部サービス / ローカル依存
- **GitHub**: kobaaam/kobaamd リポジトリ。PR 駆動、Actions リリース。**PR-level CI は無い**（`release.yml` のみ、tag push 時に動作）。検証はローカル + `kobaamd_validate_build` 頼み。
- **Linear**: kobaan workspace / `KMD` team / 接続アカウントは Linear bot 専用メール（実値は `~/.zshrc` の `LINEAR_API_KEY` から逆引き、本ドキュメントには記載しない）。Linear hosted MCP は使わない（`lq.sh` 経由のみ）。
- **OpenAI**: Codex CLI（`auth_mode: chatgpt`、gpt-5.5 デフォルト、ChatGPT Plus アカウント）。
- **Anthropic API**: wiki ヘルパー / Haiku batch / 各 subagent。
- **Google Gemini**: `gemini-3.1-pro-preview`（調査用）。
- **Sparkle update server**: `appcast.xml` がリポジトリで配信、GitHub Pages or release asset 経由 `[推測]`。
- **launchd**: ローカル Mac 上で `pipeline_active` (30 分) / `pipeline_daily` (毎日 8:00) / `pipeline_weekly` (月曜 9:00) / `pipeline_resume` (金曜 7:00) を実行。`scripts/launchd/install.sh` でロード済み前提。
- **Tart VM**（任意）: E2E 用ベース VM。`scripts/setup_tart_vm.sh` でセットアップ。`tart list | grep kobaamd-e2e-base` で確認。

### DB / クラウド / 認証
- DB: アプリ内 SQLite FTS5（`WikiIndexService`、KMD-68 で導入）。**ユーザーローカル**のみ、永続化はディスク。
- クラウド: なし（ノートはローカルフォルダ）。
- 認証: なし（オフライン優先）。AI API キーのみ Keychain（`APIKeyStore`）。

---

## 8. Git 状態

> ⚠️ 状態は時間で変わる。Codex は判断前に `git status --short --ignored` / `git branch --show-current` を再取得すること。本セクションは 2026-05-15 ハンドオフ作成時点の snapshot。

### 現在のブランチ
- `main`（リモートと同期、tracked ファイルの modified なし）

### 変更済みファイル
- tracked ファイルは modified ゼロ
- gitignored ファイル `CLAUDE.md` が AGENTS.md redirect スタブとして書き換わっている（git index 外なので本ハンドオフ作成時点で git status の `M` 列には現れない）

### 未追跡ファイル / Codex の扱い
| パス | 性質 | Codex の扱い |
|---|---|---|
| `AGENTS.md` / `agent.md` | 新しい一次資料（同内容を 2 ファイルに複製） | **本ハンドオフと併せて 1 PR でコミット候補**。人間に確認 |
| `docs/ai-handoff.md` | 本ファイル | 同上 |
| `docs/talks/` | LT 発表資料一式（pptx / pdf / md outline） | **触らない**。社内 LT の個人成果物 |
| `アウトライン.md`（ルート） | LT スライドのアウトライン | **触らない**。`docs/talks/` 配下と内容重複の可能性が高い `[推測]` |

### Codex が触ってよい / 触らない方がよいファイル

**触ってよい**:
- `Sources/**`（実装本体）
- `Tests/**` / `E2ETests/**`
- `docs/wiki/articles/**`（subagent 経由が望ましいが手動編集も可）
- `docs/learnings/**`, `docs/adr/**`, `docs/prd/**`
- `.claude/agents/**`, `.claude/commands/**`（プロンプト改善）
- `scripts/**`（特に `scripts/wiki/`, `scripts/linear/`, `scripts/launchd/`）
- `README.md`, `CONTRIBUTING.md`, `Package.swift`

**触らない方がよい**:
- `Info.plist`(`SUPublicEDKey` 周辺。post-build に任せる)
- `appcast.xml`（リリース時に自動更新）
- `.git/**`, `.build/**`, `.cache/**`, `.logs/**`（生成物）
- `AGENTS.md` / `agent.md` — **プロジェクト最上位ルールの新一次資料**。Codex 大規模改訂は人間承認必須。
- `CLAUDE.md` — AGENTS.md への入口（redirect スタブ）。原則触らない。
- 未追跡の LT 資料 2 件（`docs/talks/` と `アウトライン.md`）
- `eddsa_priv*` / `*_priv_key*` / `*.pem`（gitignore 済みだが念のため。`Tests/Resources/*.pem` は **現時点で実体なし**だが whitelist exception が `.gitignore` に予約されている）

### コミット可能な単位の提案
- **本体実装のコミット候補は現状なし**（modified ゼロ）。
- **ハンドオフ文書一式（`AGENTS.md` / `agent.md` / `docs/ai-handoff.md`）は untracked のコミット候補**。これらは「Codex 引き継ぎ準備」という単一目的の塊なので、`infra: codex 引き継ぎ資料の追加 (AGENTS.md / docs/ai-handoff.md)` のような **1 PR**にまとめるのが妥当。コミット前に人間（kobaaam）に確認すること。
- Codex が新たに実装を始めたら **1 機能 = 1 PR / 1 修正 = 1 PR**（`AGENTS.md`「PR ルール」準拠）。
- LT 資料（`docs/talks/` と `アウトライン.md`）を commit するなら **単独 PR + `docs:` プレフィックス**にして本体変更や上記ハンドオフ PR と混ぜないこと。

---

## 9. オーケストレーション方針

### Codex 親エージェントの位置づけ（AGENTS.md 由来）

- **親 (Orchestrator / Architect)** は **gpt-5.5、reasoning medium〜high** で動く。設計判断・統合・最終レビュー・ユーザー説明に集中。
- 以下の用途は **subagent に委譲**して親 context と token を節約する:
  - **Explorer** (gpt-5.4-mini, reasoning low〜medium): `rg` 探索、関連ファイル特定、類似実装調査
  - **Worker** (gpt-5.4 or gpt-5.3-codex, reasoning medium): 担当ファイルが明確な小〜中規模実装
  - **Verifier** (gpt-5.4-mini, reasoning low): テスト実行、失敗ログの一次分析、リスク要約
  - **Batch / Summary** (gpt-5.4-mini, reasoning low): ドキュメント要約・Issue 整理・構造化判定
- subagent 委譲時は **担当範囲を明示** + **無関係な変更/revert 禁止** を必ず指定。返答は「変更ファイル / 検証コマンド / 未検証リスク」だけに絞る。
- 詳細は [`AGENTS.md`](../AGENTS.md) 「Codex 優先ルール」を参照。

### Codex に任せたい判断範囲
- `Sources/**` への実装変更（バグ修正・新機能 UI）。AGENTS.md の「Claude Code からの移管情報」では「`.swift` は Codex 担当」と明示済み。
- Test の追加 / 修正。
- リファクタリング（動作変更なし）。
- `scripts/` の小規模改善。
- 既存 subagent / slash の **プロンプト微調整**（`.claude/agents/` / `.claude/commands/`、ただしこれらは Claude Code 専用なので Codex は仕様確認のみ実行）。
- PR 作成・自身がレビューを受ける側に回ること。

### 人間の承認が必要な操作

**プロジェクトワークフロー由来（旧来から）**:
- **backlog → todo 昇格**（priority を 3 以上に上げる or `ai-research` ラベルを外す）。AI はここに触れない。
- **`Human in Review` での仕様判断回答**（Linear コメントで人間が返答）。
- **`[BREAKING]` 変更**: public API 削除・メジャー dep 更新・データフォーマット破壊。PR タイトルに `[BREAKING]` を付け、必ず `Human in Review` に入れる。
- **Sparkle 秘密鍵 / 公開鍵の更新**。
- **`main` への直接 push**（hook でブロック済みだが、bypass しないこと）。
- **`AGENTS.md` / `agent.md` / `docs/wiki/SCHEMA.md` の大規模改訂**（最上位ルールの変更）。
- **launchd 再インストール / アンインストール**（`scripts/launchd/install.sh` / `uninstall.sh` 等）。

**Codex sandbox 由来（実行制約として）** — 以下は Codex が自動承認なしに走らせると人間に余分なポップアップを出すか、想定外の副作用が出る:
- **Linear への write**: `lq.sh issue.create` / `lq.sh issue.update` / `lq.sh issue.transition` / `lq.sh issue.archive` / `lq.sh comment.add`。**先に `LQ_DRY_RUN=1` で payload を確認**してから本実行する。
- **GitHub への write / push**: `gh pr create` / `gh pr merge` / `gh pr close` / `gh issue create` / `gh issue close` / `gh release create` / `git push` 等。これらは **dry-run 相当がない**ため、実行コマンド・PR タイトル / body・push 先ブランチを **必ず人間に提示してから確認の上で実行**する（特に main 系 / tag push / release create）。`gh pr create --draft` を経由してから ready 化するパターンも検討。
- **ブラウザ / GUI 起動**: `open .build/kobaamd.app` / `open https://...` / `xed` 等。Codex sandbox では別承認が要求される想定。
- **launchd 操作**: `launchctl load/unload/start/stop` は OS state を変える。手動承認の上で実施。
- **依存インストール**: `brew install ...` / `pip install ...` / `npm install -g ...`。ローカル環境を恒久的に変えるため要承認。
- **codesign / notary 周辺**: `codesign --options runtime ...` / `xcrun notarytool ...` は鍵運用に絡む。
- **大量バッチ実行**: `scripts/wiki/ask.sh` / `kobaamd_lint_section_context` を全件回す類は **`scripts/usage/check.sh` で事前確認**してから。
- **Tart VM 操作**: `tart run` / `tart delete` などは VM ステート変更、要確認。

### 並列化できるタスク
- `kobaamd_review_pr` と `kobaamd_review_security` は並行実行可能（`pipeline_active` フェーズ B が既にそう動かしている）。
- 異なる issue（KMD-185, KMD-186, KMD-188, KMD-189 など carve-out 群）への着手は WIP=1 ルールを守る限り独立。ただし `kobaamd_assign_work` は **1 件選定の slash**なので、Codex が複数同時着手したい場合は手動で issue を選び、それぞれ別 feature branch を切ること。
- wiki ingest と postmortem 書き出しは依存関係がないので並行可。

### 自動パイプラインと手動オーケストレーションの競合回避
- **`pipeline_active` は launchd で 30 分ごとに自動起動中**（事実: PID 27804 観測）。Codex が手動で `In Progress` / `in Review` 状態の issue を触っていると、次回起動で `recover_halted` / `fix_pr_comments` 等が同じ issue を奪い合う可能性がある。
- 長時間の手動セッションを始める前に、必要に応じて `launchctl unload ~/Library/LaunchAgents/com.kobaamd.pipeline_active.plist` で一時停止し、終了後 `load` で復帰させること。**`uninstall.sh` を呼ばないこと**（プロジェクト永久 disable 扱いになる）。
- `pipeline_active` フェーズ B には **1 起動あたり最大 5 サイクル**の上限あり（`.claude/commands/kobaamd_pipeline_active.md` で確認）。新規 issue 完全サイクル（PRD → 実装 → レビュー → マージ → postmortem）が 5 件を超えるとそのバンドル内では止まる。

### 5 分以内に連続呼び出しすべきタスク（Anthropic Prompt Cache 5 分 TTL）
- `scripts/wiki/ask.sh` を **5 分以内に連続呼び出し**すると wiki 全文が cache hit になり大幅にコスト低下。複数の wiki クエリは続けざまに実行すること。
- 同様に `kobaamd_lint_section_context`（Haiku）のバッチ判定もセッション継続が前提。

### リリース手順（参考、Codex は人間承認なしでは tag push しない）
- リリースは `git tag vX.Y.Z && git push origin vX.Y.Z` でトリガー（`.github/workflows/release.yml` の `on: push: tags: ['v*']`）。
- 必須 secrets: `SU_PUBLIC_ED_KEY` / `SPARKLE_EDDSA_PRIVATE_KEY`（GitHub Settings → Secrets で設定済み）。
- `Info.plist` の `CFBundleShortVersionString` は現状 `0.7.0`、次バージョン更新は手動 commit が必要。
- リリース後 `appcast.xml` が自動更新される（KMD-182）。push 失敗時 silent failure が残る既知の小バグは KMD-197 で carve 済み。

### 破壊的操作 / 禁止事項
- `git push --force` を `main` に対して行うこと（**絶対禁止**）。
- `git reset --hard` で他人の作業（未追跡含む）を破棄すること。
- `.git/hooks/` の bypass（`--no-verify` / `--no-gpg-sign`）。
- `eddsa_priv*` / `*.pem`（テスト用以外）をコミットすること。
- `.env` / API キー / トークン / `LINEAR_API_KEY` 等を **ログ出力 / commit / PR 本文に書く**こと。
- `kobaamd_archive_done` を不必要に走らせる（Linear free plan の 250 issue 制限管理用、AI ループで多発させない）。
- launchd plist を直接書き換える（`scripts/launchd/install.sh` 経由のみ）。
- 外部 API（OpenAI/Anthropic/Gemini）への巨大バッチを夜間以外に流す `[推測]` のコスト管理ルールは memory に残っていないが、`scripts/usage/` に pre-usage check が KMD-128 で追加済み。

---

## 10. 次の推奨アクション（Codex 用チェックリスト）

Codex 引き継ぎ直後を想定。**A: 状況把握 → B: 環境確認 → C: タスク着手 → D: 検証 → E: PR 化** の 5 ブロックで順に実行する。

### A. 状況把握（読み専用、副作用なし）
1. [ ] `cat AGENTS.md` — **最優先**。Codex 優先ルール / モデル割り当て / 「Claude Code からの移管情報」を確認。
2. [ ] `cat docs/ai-handoff.md`（本ファイル）— 全体像とハンドオフ意図を取り込む。
3. [ ] `git status --short --ignored` と `git branch --show-current` — 現状を **再取得**（このドキュメント記載は snapshot に過ぎない）。
4. [ ] `gh pr list --state open --limit 20` — 開いている PR を **再取得**。本作成時点では postmortem 系 8 件のみ。

### B. 環境確認（読み専用 + 軽い probe）
5. [ ] `env | cut -d= -f1 | rg -i '^(LINEAR_API_KEY|OPENAI_API_KEY|GEMINI_API_KEY|ANTHROPIC_API_KEY)$'` — **キー名のみ**で存在確認（値は出力しない）。居なければ §4 の `zsh -lic` 経由で限定的に取り込む（`source ~/.zshrc` は alias 副作用があるので避ける）。
6. [ ] `./scripts/usage/check.sh` — API 利用窓の確認。exit 10 なら閾値超過、subagent 大量起動を控える。
7. [ ] `launchctl list | grep kobaamd` — 自動パイプラインの生存状況。`pipeline_active` が回っている場合、手動オーケストレーションと衝突しないよう注意（§9「自動パイプラインと手動オーケストレーションの競合回避」参照）。

### C. タスク選定と着手
8. [ ] `./scripts/linear/lq.sh issue.list --team KMD --state Todo --limit 30` — Todo を **再取得**。
9. [ ] 1 件選び、PRD（`docs/prd/<KMD-XX>-*.md` または Linear issue body）と関連 wiki 記事を `scripts/wiki/ask.sh` で確認。
10. [ ] `git checkout -b feature/KMD-XX-<slug>` で feature branch 作成。
11. [ ] `./scripts/linear/lq.sh issue.transition KMD-XX "In Progress"`（先に `LQ_DRY_RUN=1` で payload を確認してから本実行）。

### D. 検証
12. [ ] `swift build` — クリーンビルド確認（**事実: 2026-05-15 時点で 2.89s に成功**）。
13. [ ] `swift test 2>&1 | tee /tmp/test.log` — 既知ギャップで結果行が出ない可能性大。**PR の Test plan には「swift test は実質 no-op の可能性、手動 / E2E で代替」を必ず明記**（§4 の検証ギャップ注記）。
14. [ ] `./scripts/post-build.sh` — `.app` バンドル化。
15. [ ] **GUI 動作確認**は `open .build/kobaamd.app` だが、Codex sandbox では別承認 / 人間確認段階。**ローカル検証が事実上のゲート**（PR-level CI は無い）。

### E. PR 化 / 進行
16. [ ] PR 作成: `gh pr create --title "KMD-XX: <要約>" --body ...`。タイトルプレフィックス `KMD-XX:`、body に Summary + Test plan。Co-authored-by 規約は §5「既存のローカル規約」参照。
17. [ ] Linear `In Progress → in Review` 遷移（`lq.sh issue.transition`）。
18. [ ] `kobaamd_review_pr` 相当の自動レビュー待ち（pipeline_active が拾う）。Codex が直接走らせる場合は Worker subagent に「`.claude/agents/kobaamd_review_pr.md` を読んで等価の手順を踏む」と指示する。
19. [ ] APPROVE クリーン → `kobaamd_merge_pr` 相当でマージ → done。`Human in Review` 行きなら人間レス待ち。
20. [ ] done 後の `review_postmortem` → `update_wiki` は pipeline が自動で回す。

---

## 11. 補足: コマンド実行結果サマリ（2026-05-15 ハンドオフ作成時点で実測）

### `git status --short --ignored`
```
?? AGENTS.md
?? agent.md
?? docs/ai-handoff.md
?? docs/talks/
?? "\343\202\242\343\202\246\343\203\210\343\203\251\343\202\244\343\203\263.md"
!! .DS_Store
!! .build/
!! .cache/
!! .claude/.DS_Store
!! .claude/settings.local.json
!! .logs/
!! CLAUDE.md
!! dist/
...
```
（tracked modified ゼロ。AGENTS.md / agent.md / docs/ai-handoff.md が新規 untracked。CLAUDE.md は `.gitignore` 対象で redirect スタブに変更済み）

### `git branch --show-current`
```
main
```

### `rg --files | head`
```
Info.plist
LICENSE
README.md
アウトライン.md
Package.resolved
CONTRIBUTING.md
appcast.xml
Package.swift
E2ETests/generate_xcodeproj.sh
E2ETests/kobaamdE2ETests/Info.plist
```
（合計 275 ファイル、`rg --files | wc -l`）

### 主要設定ファイルの有無
| ファイル | 有無 | 補足 |
|---|---|---|
| `Package.swift` | ✅ あり | SPM、`swift-tools-version:5.9`、macOS 14+ |
| `Package.resolved` | ✅ あり | swift-markdown / Sparkle / tree-sitter |
| `package.json` | ❌ なし | Node 依存なし |
| `pyproject.toml` | ❌ なし | Python 依存なし |
| `Cargo.toml` | ❌ なし | Rust 依存なし |
| `Makefile` | ❌ なし | 代わりに `scripts/` シェル群 |
| `.github/workflows/release.yml` | ✅ あり | KMD-182 で導入された DMG リリース CI |
| `.mcp.json` | ⚠️ ファイル存在するが gitignore 対象 | Linear MCP は撤去済み、`scripts/linear/lq.sh` に統一 |

### テスト / ビルド / lint 実行結果
| コマンド | 結果 | 補足 |
|---|---|---|
| `swift build` | ✅ `Build complete! (2.89s)` | warning なし |
| `swift test` | ⚠️ `Build complete!` のみ出力、テスト結果行なし、exit 0 | §4 の既知問題。Swift Testing が SwiftPM ランナーで discover されていない可能性 |
| `which swift-format` | ❌ `swift-format not found` | brew / xcrun に未インストール |
| `swift --version` | ✅ `Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108 clang-2100.1.1.101)` / target `arm64-apple-macosx26.0` | Package 指定の macOS14 と CLT SDK の macosx26 にギャップあり |
| `gh auth status` | ✅ account `kobaaam` active、scopes `gist, read:org, repo, workflow` | second account `kobaan-bst` 非 active で同居 |
| `launchctl list \| grep kobaamd` | ✅ `pipeline_active` PID 27804（稼働中）、`pipeline_daily` / `pipeline_weekly` ロード済（待機） | `pipeline_resume` は記録なし（金曜のみ起動） |
| `.claude/agents` ファイル数 | 14 | AGENTS.md の「10 subagent」記載は **古い** |
| `.claude/commands` ファイル数 | 28 | AGENTS.md の「20 slash command」記載は **古い** |
| `gh pr view 112 --json statusCheckRollup` | `[]` | **PR-level CI は無効**（release.yml は tag push 時のみ）。事実上ローカル検証ゲート |

---

## 12. このドキュメントの更新ルール

- 実装中に状況が変わったら、Codex 側で本ファイルの該当セクションを **小規模 PR** として更新する。
- 大規模な引き継ぎフェーズの切れ目（フェーズ移行 / 大規模 refactor 着手 / リリース直後）でリフレッシュ。
- Linear ステータスや PR 件数は時間で変動するので、**最終更新日と数字は必ず実行コマンドで再取得**してから書き換える。
- `[推測]` 印は事実確認ができたら削除し、出典（コミット / ファイルパス / Linear issue）を残す。

---

## 13. レビュー履歴（self-audit）

| 日時 | 視点 | 主な追記 |
|---|---|---|
| 2026-05-15 / Cycle 1 | AGENTS.md 移行の検出 | AGENTS.md / agent.md を最優先資料に格上げ、CLAUDE.md スタブ化を反映、Codex 専用 orchestration roles (Orchestrator/Explorer/Worker/Verifier/Batch) を §9 に追加、`scripts/usage/check.sh` と `scripts/recovery/recover_halted.sh` を §3 に追加、`Sources/CLI/MCPServer.swift` の dual-purpose 性質を §3 に追加、§10 チェックリストを 16 ステップに拡張 |
| 2026-05-15 / Cycle 2 | 手動 vs 自動パイプラインの衝突視点 | Phase 4 が事実上完了している点を §6 に明記、ローカル CLI ツールチェイン表を §7 に追加、`pipeline_active` との衝突回避手順 + 5 cycle 上限 + Prompt Cache 5 分 TTL の活用法を §9 に追加、リリース手順（tag push トリガー）を §9 に追加、コマンド実測サマリ §11 に gh auth / launchctl / agents/commands ファイル数 / PR-level CI 無効を追加、AGENTS.md 内の subagent / slash 数記載が古いことを明示 |
| 2026-05-15 / Codex フィードバック対応 #1 | Codex 側から実投入前レビュー（15 件指摘） | git status §2 を `--ignored` 付きで再取得し AGENTS.md / agent.md / CLAUDE.md スタブ化を反映 / CLAUDE.md の「5 行」表現を撤回 / §10 の "cat CLAUDE.md" 誤誘導を AGENTS.md に修正 / Claude モデル表に「Codex は AGENTS.md 優先」注記 / `.claude/agents/` `.claude/commands/` は Claude Code 専用で Codex は仕様参照のみと明記 / `/kobaamd_format_code` の代替素コマンドを §4 に / `open .build/kobaamd.app` をビルドステップから分離 / `swift test` no-op 危険性を「PR Test plan に必ず明記」と強調 / `source ~/.zshrc` の alias 副作用警告と `zsh -lic` 代替を §4 に / Co-authored-by 規約を Codex 引き継ぎ後向けに §5 に / AGENTS.md / CLAUDE.md の改訂承認を §9 に明示 / Codex sandbox 承認境界（外部 write / GUI / launchd / 依存導入 / Tart VM / 大量バッチ）を §9 に追加 / Linear / PR snapshot に「再取得して判断」注記を §2 / §10 / §8 に追加 / Linear 接続アカウントの個人メールを §7 から削除しぼかし表現に変更 / §10 チェックリストを A〜E の 5 ブロック 20 ステップに再編成 |
| 2026-05-15 / Codex フィードバック対応 #2 | Codex 側から 2 巡目レビュー（6 件指摘、主に安全性 + 矛盾解消） | §4 と §10 step 5 の `env | rg` を `env \| cut -d= -f1 \| rg ...` / `printenv ... >/dev/null` 系に置換（値リーク防止） / §8 「コミット可能な単位の提案」を本体実装ゼロ + ハンドオフ文書一式 (AGENTS.md / agent.md / docs/ai-handoff.md) を 1 PR 候補、と矛盾解消 / §1 の "CLAUDE.md 参照" を `AGENTS.md`「Claude Code からの移管情報」参照に / §5 の `NSTextView` 注記と Linear I/O 注記を `AGENTS.md` 系参照に変更 / §3 の `.claude/agents/*.md` と `.claude/commands/kobaamd_pipeline_active.md` の表エントリにも「Claude Code 専用、Codex は仕様参照のみ」を明記 / §5 Co-authored-by を「正式表記未確認 → 確認まで co-author を付けない」運用に変更（推測の `noreply@openai.com` 削除） / §1 ディレクトリ表の `Sources/CLI/` から `[推測]` を外し、`MCPEntryPoint` / `MCPProtocol` / `MCPServer` / `VaultPath` / `WikiSearchIndex` / `Tools/` の具体構成と KMD-69 出典を明記 |
| 2026-05-15 / Codex フィードバック対応 #3 | Codex 側 3 巡目レビュー（4 件指摘、安全性 + 誤誘導の精度上げ） | §3 `CLAUDE.md` 行を「ローカル redirect スタブ・gitignored・fresh clone に無い可能性」と明示 / §9 外部 write 承認境界を Linear (lq.sh の `LQ_DRY_RUN=1`) と GitHub (gh / git push、dry-run 無、人間に提示してから実行) に分離 / §5 PRD Section 11 Gemini 調査ログに **redaction 注意**追加（OSS commit リスクの明示）/ §1 冒頭注記に「AGENTS.md 内 Claude Code 由来コマンド例（`source ~/.zshrc` 直呼び・`curl` URL に API キー埋め込み）は履歴資料、Codex は §4 の安全な代替を優先」を追記 |
| 2026-05-15 / Codex フィードバック対応 #4（最終確認） | Codex 4 巡目: 4 件すべて反映確認 + 致命的問題なし判定 | **PR 化 OK** の判定取得。本ハンドオフは fresh Codex に渡せる状態 |
