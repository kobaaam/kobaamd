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

## ⚠️ 厳守ルール：役割分担（最重要）

> **このルールを守らないことは、プロジェクトの開発体制を壊すことと同義です。**
> Claudeが直接コードを書くことは原則禁止です。

### Claude が単独でやること（これだけ）
- アーキテクチャの判断・設計
- コードレビュー・方針のすり合わせ
- バグの根本原因の特定
- Codex / Gemini へのプロンプト作成と結果の取り込み

### Codex に必ず依頼すること
以下に該当する作業は **必ずCodexを呼び出してから実装すること**。自分でコードを書いてはいけない。

| 作業カテゴリ | 例 |
|---|---|
| SwiftUI View の追加・変更 | TabBarView, SplitDivider, ツールチップ追加など |
| ViewModel / Service の追加・変更 | openInTab(), タブ管理メソッドなど |
| バグ修正（コード変更を伴うもの） | Mermaid修正, 段ずれ修正など |
| リファクタリング | height統一, header削除など |
| AppDelegate / App エントリポイントの変更 | WindowGroup→Window切り替えなど |

**判断基準**: `.swift` ファイルを新規作成・編集するなら → **Codexに依頼**

### Gemini に必ず依頼すること
- 技術調査・選定比較
- ドキュメント生成（README, CONTRIBUTING など）
- デザイン方針の相談

---

### Codex 呼び出し手順（実装依頼のテンプレート）

```bash
source ~/.zshrc
PROMPT="以下のSwift/SwiftUIコードを実装してください。\n\n【目的】\n...\n\n【対象ファイル】\n...\n\n【変更内容】\n..."
curl -s https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$(jq -n --arg p "$PROMPT" '{model:"gpt-5.1-codex-mini", input:$p}')" \
  | jq -r '(.output[] | select(.type=="message") | .content[0].text)'
```

### Gemini 呼び出し手順

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
> **注意**: Geminiへのプロンプトは日本語特殊文字が含まれる場合、必ずファイル経由で渡すこと

---

## 作業フロー（automode用）

1. ユーザーの要求を受ける
2. **Gemini** に調査・設計相談（必要な場合）
3. Claude がアーキテクチャを決定・Codexへのプロンプトを設計
4. **Codex** に実装を依頼し、出力をレビューしてファイルに反映
5. ビルド確認（`swift build && ./scripts/post-build.sh && open .build/kobaamd.app`）
6. APIキー・秘密情報は絶対に出力しない

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
