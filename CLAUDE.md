# kobaamd — Claude Code 引き継ぎ資料

## プロジェクト概要

Mac Native Markdownエディタ。詳細は `PRD.md` / `ARCHITECTURE.md` を参照。

**ビジョン**: AIが生成したMarkdownを、Macで最も快適に扱えるエディタ
**技術**: SwiftUI + AppKit / macOS 14以降 / OSSリリース予定

---

## 開発体制・LLM構成

| ペルソナ | LLM | 用途 |
|---------|-----|------|
| Orchestrator / PM / Architect | **Claude（自分）** | 統括・設計・コアロジック実装 |
| UI Coder / Refactor | **OpenAI Codex** (`gpt-5.1-codex-mini`) | SwiftUI実装・コード最適化 |
| Researcher / DocWriter | **Gemini** (`gemini-2.5-flash`) | 調査・ドキュメント生成 |

### APIキー
- `$OPENAI_API_KEY` — `~/.zshrc` に設定済み
- `$GEMINI_API_KEY` — `~/.zshrc` に設定済み
- **必ず `source ~/.zshrc` してから使うこと**

### Codex 呼び出し
```bash
source ~/.zshrc
curl -s https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$(jq -n --arg p "プロンプト" '{model:"gpt-5.1-codex-mini", input:$p}')" \
  | jq -r '(.output[] | select(.type=="message") | .content[0].text)'
```

### Gemini 呼び出し（プロンプトをファイル経由で渡す）
```bash
source ~/.zshrc
cat > /tmp/req.json << 'EOF'
{"contents": [{"parts": [{"text": "プロンプト"}]}]}
EOF
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @/tmp/req.json \
  | jq -r '.candidates[0].content.parts[0].text'
```
> **注意**: Geminiへのプロンプトは日本語特殊文字が含まれる場合、必ずファイル経由で渡すこと（curlのインラインJSONはjqのパースエラーが発生する）

---

## 現在のフェーズ

**Phase 0（完了）**: PRD・アーキテクチャ設計
**Phase 1（完了）**: MVP実装（Tasks 1〜7、2026-04-20）
**Phase 2（次）**: 保存機能・エラーハンドリング・UX改善

---

## 技術選定（確定済み）

| 領域 | 採用 |
|------|------|
| アーキテクチャ | MVVM（`@Observable`） |
| エディタ | `NSTextView` AppKitラップ |
| Markdownパーサー | `swift-markdown`（Apple製） |
| シンタックスハイライト | 正規表現ベース → TreeSitter（v2） |
| ダイアグラム | Mermaid.js（WKWebView） |
| AI連携 | REST API（マルチプロバイダー） |

詳細は `ARCHITECTURE.md` を参照。

---

## Phase 1 タスク一覧（優先順）

1. Xcodeプロジェクト作成・ディレクトリ構成
2. 基本ウィンドウ（3ペイン: サイドバー / エディタ / プレビュー）
3. フォルダツリー + ファイル開閉
4. NSTextView エディタ（基本編集）
5. swift-markdown リアルタイムプレビュー
6. シンタックスハイライト（正規表現ベース）
7. 全文検索

---

## 作業ルール（automode用）

- **コード実装はCodexに依頼する**。Claudeはアーキテクチャ判断・レビュー・コアロジックを担当
- **調査・ドキュメントはGeminiに依頼する**
- タスクは上記リストを上から順に進める
- 各タスク完了後、次のタスクを自動で開始する
- APIキー・秘密情報は絶対に出力しない
- コードはリポジトリ内（`/Users/h.kobayashi02/atelier/kobaamd/`）に書く

---

## 未解決事項（TBD）

- プレビューモード: 2ペイン vs シームレス（デフォルト）
- AI APIキー管理: Keychain経由（方針確定、実装はPhase 2）
- TreeSitter Swift バインディングの選定（v2以降）

---

## 行動原則（Karpathy Guidelines）

### 1. Think Before Coding
コードを書く前に問題を理解する。何を解決しようとしているのか、なぜそのアプローチが正しいのかを明確にしてから実装する。

### 2. Simplicity First
最もシンプルな解決策を選ぶ。複雑な抽象化や過剰な設計は避ける。今必要なものだけを実装する。

### 3. Surgical Changes
変更は最小限・ピンポイントに。関係のないコードは触らない。diff が小さいほど良い。

### 4. Goal-Driven Execution
ゴールから逆算して行動する。タスクの完了基準を明確にし、それに向けて最短経路を取る。途中の作業が目的化しない。
