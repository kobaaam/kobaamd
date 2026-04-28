---
linear: KMD-19
status: in-progress
created_at: 2026-04-27
author: kobaamd_create_prd subagent
---

# マルチターン AI チャットサイドバー

## 1. 背景・目的

kobaamd のビジョン「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」において、現在の `AIAssistPanel.swift` は選択テキストを単発で AI に送信する one-shot 方式にとどまる。実際の AI 共同執筆フローでは「この節を書いて → フィードバックして → もう少し短くして」というマルチターンの会話が不可欠であり、現状では ChatGPT / Claude.ai 等を別ウィンドウで開いてコピペするという迂回が必要になる。

会話履歴を保持したまま kobaamd 内で AI と対話できるサイドバーを持つことで、エディタから離れずに AI 共同執筆を完結させる体験が実現する。これは kobaamd を「AI 生成コンテンツを扱うエディタ」から「AI と一緒に書くエディタ」へ昇格させる機能であり、他の macOS Markdown エディタとの最大の差別化点になる。

既存の `AIService.swift`（マルチプロバイダー対応）と `APIKeyStore.swift` はそのまま活用できるため、実装はサイドバー UI と会話履歴管理の ViewModel 追加に集中できる。

## 2. ターゲットユーザーとユースケース

**ペルソナ A — AI ドキュメント共同執筆者**: Claude に「この README の構成を提案して」と聞き、提案をもとに「第3節をもっと詳しく」「コードブロックを追加して」と会話を続けながら文書を構築する。会話履歴が残るため、前の提案を参照しながら refinement を続けられる。

**ペルソナ B — AI レビュアーとの対話**: 書き終えた文書をサイドバーに貼り、「この文章の問題点は？」「英語として自然か？」と逐次確認しながら推敲する。会話コンテキストが保持されるため、「さっきの指摘の3点目だけ直して」という指示が通る。

**ペルソナ C — プロバイダー切り替えユーザー**: 同じ会話の中で OpenAI から Anthropic に切り替えて比較したい。プロバイダーセレクターをチャット UI に常設する。

## 3. 機能要件

### 必須要件

* `AIChatViewModel.swift`（新規）を作成し、`[ChatMessage]` 配列（`role: user/assistant`、`content: String`、`timestamp: Date`）を保持すること
* `AIChatView.swift`（新規）をメインウィンドウの右端サイドバーとして実装すること（`MainWindowView.swift` に追加）
* 既存の `AIAssistPanel.swift` は現状維持（廃止しない）し、`⌘E` の動作は変更しないこと。チャットサイドバーは新規ショートカット（`⌘⇧E`）で開閉すること
* `AIService.swift` のマルチプロバイダー対応（OpenAI / Anthropic）をそのまま利用し、`messages` 配列を API リクエストの `messages` フィールドに渡すこと
* 各アシスタントメッセージに「エディタに挿入」ボタン（エディタ末尾に追記）を配置すること
* 会話履歴はメモリ内保持のみ（アプリ再起動でリセット）。永続化は v2 以降とすること
* 「会話をクリア」ボタンで `[ChatMessage]` 配列をリセットできること

### オプション要件

* ユーザーメッセージの編集・再送信（上矢印で過去メッセージを編集）
* 推定トークン数の表示（OpenAI API の usage フィールドを利用）
* ファイルごとの会話履歴分離（タブ切り替え時に独立した履歴を保持）

## 4. 非機能要件

* **パフォーマンス**: API 呼び出しは `async/await` で非同期実行し、ストリーミング対応（`AIService.stream`）を使い逐次表示すること。会話履歴が 100 メッセージを超えた場合は古いメッセージをトリムすること。
* **アクセシビリティ**: チャット履歴の `ScrollView` に `accessibilityLabel("AI chat history")` を設定すること。各メッセージバブルに role（ユーザー/アシスタント）を `accessibilityValue` で明示すること。
* **macOS 整合性**: サイドバーの幅は 320px 固定で開始（ドラッグ調整は v2）。チャット UI のカラーは既存デザイントークン（`Color.kobaAccent`、`Color.kobaPaper`、`Color.kobaSurface`）を使用すること。

## 5. UI/UX

メインウィンドウの右端にチャットサイドバーを追加:

```
+----------+------------------+------------------+---------------+
| Sidebar  | Editor           | Preview          | AI Chat       |
| (240px)  | (split frac)     | (残り)           | (320px)       |
|          |                  |                  |               |
|          |                  |                  | [OpenAI v]    |
|          |                  |                  | ─────────     |
|          |                  |                  | [User]        |
|          |                  |                  | README 構成   |
|          |                  |                  | を提案して    |
|          |                  |                  |               |
|          |                  |                  | [AI]          |
|          |                  |                  | 以下の構成    |
|          |                  |                  | を提案...     |
|          |                  |                  | [挿入]        |
|          |                  |                  |               |
|          |                  |                  | [User]        |
|          |                  |                  | 3節を詳しく   |
|          |                  |                  | ─────────     |
|          |                  |                  | [TextField ]  |
|          |                  |                  | [送信] [クリア|
+----------+------------------+------------------+---------------+
```

* ユーザーメッセージ: 右寄せ、`Color.kobaAccent.opacity(0.1)` 背景の `RoundedRectangle`
* アシスタントメッセージ: 左寄せ、`Color.kobaSurface` 背景 + 「エディタに挿入」ボタン（右下に `.font(.system(size: 10))`）
* 入力エリア: 最下部に `TextField` + 「送信」ボタン（`Color.kobaAccent`）+ 「会話をクリア」ボタン

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `⌘⇧E` でチャットサイドバーが開閉できること
- [ ] チャットサイドバーでユーザーメッセージを送信すると AI の返答がサイドバーに表示され、会話履歴として蓄積されること（2往復以上の連続会話で確認）
- [ ] アシスタントメッセージの「エディタに挿入」ボタンを押すと、エディタの末尾にテキストが挿入されること
- [ ] 「会話をクリア」ボタンを押すと会話履歴がリセットされ、チャット履歴 UI が空になること
- [ ] 既存の `⌘E` による one-shot `AIAssistPanel` の動作が変わらないこと（後退互換）
- [ ] `swift build` でビルドエラーが 0 件であること

## 7. テスト戦略

* **単体テスト対象ファイル**:
  * `Sources/ViewModels/AIChatViewModel.swift`（新規） — `appendMessage(role:content:)` メソッドの動作確認、100 メッセージ超のトリムロジックテスト
* **手動確認項目**:
  1. `swift build` でビルド確認
  2. チャットサイドバーを開き、OpenAI / Anthropic それぞれのプロバイダーで送受信が動作することを確認
  3. 3往復以上の会話をして、2回目以降の返答が前の会話コンテキストを反映していることを確認
  4. 「エディタに挿入」ボタンを押してエディタへの挿入を確認
  5. `⌘E` で既存 AIAssistPanel が正常に開くことを確認（後退互換）

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Views/MainWindowView.swift` | 変更 | 右端チャットサイドバー追加、`⌘⇧E` ショートカットハンドリング追加 |
| `Sources/ViewModels/AIChatViewModel.swift` | 追加 | 新規ファイル。`ChatMessage` モデルも同ファイルに定義 |
| `Sources/Views/AI/AIChatView.swift` | 追加 | 新規ファイル |
| `Sources/App/AppCommand.swift` | 変更 | `aiChat` case 追加（`kobaamd.aiChatRequested`） |
| `Sources/App/AppViewModel.swift` | 変更 | `isChatSidebarVisible: Bool` プロパティと `AIChatViewModel` インスタンス追加 |
| `Sources/Services/AIService.swift` | 変更 | `streamChat(messages:provider:)` オーバーロード追加（`messages` 配列を渡す新 API）|
| `Sources/App/kobaamdApp.swift` | 変更 | `⌘⇧E` キーバインドのメニューコマンド追加、`aiChatRequested` Notification.Name エイリアス追加。PDF 書き出しが `⌘⇧E` と競合していたため PDF を `⌘⇧P` に変更 |
| `Sources/Views/AI/AIAssistPanel.swift` | 変更なし | 既存 one-shot UI は保持 |

**共有コンテナへの注意**（複数機能が同居するファイルを変更する場合は必ず記載）:
- 対象ファイルを使っている他機能:
  - `MainWindowView.swift`: サイドバー（FileTree/Search/TODO）、エディタ、プレビュー、QuickOpen、DiffSheet、AIAssistPanel が同居。`HStack` に右サイドバーを追加すると幅計算が変わるため、`SplitDivider.availableWidth` の扱いに注意する
  - `AppViewModel.swift`: タブ管理・ファイル保存・AI インライン補完・QuickOpen 等が同居。`isChatSidebarVisible` と `AIChatViewModel` の追加のみで他プロパティを変更しない
  - `AppCommand.swift`: 全コマンドが同居。`aiChat` case の追加のみ（既存 case の変更・削除禁止）
  - `AIService.swift`: `stream()` と `complete()` が各プロバイダーに実装済み。新規オーバーロード `streamChat(messages:provider:)` を追加するのみで既存メソッドのシグネチャ変更禁止

- 変更してはいけない箇所:
  - `AIAssistPanel.swift` — 既存 one-shot パネルは変更禁止
  - `AppCommand.aiAssist` (`.aiAssistRequested`) — 既存ショートカット `⌘E` を変更禁止
  - `AIService.complete()` / `AIService.stream()` の既存シグネチャ — 変更禁止（新規オーバーロードのみ追加可）
  - `AIServiceProtocol` の既存メソッドシグネチャ — 変更禁止
  - `SidebarView.swift` — 左サイドバーは変更禁止
  - `MainWindowView.StatusCommandBar` / `KobaDivider` / `SplitDivider` / `KbdHint` 等の既存コンポーネント — 変更禁止
  - `MainWindowView` の `isDiffSheetPresented`、`isQuickOpenPresented` 等の既存 State — 変更禁止（新規 State を追加するのみ）

### その他リスク

* **API コスト**: マルチターンはトークン消費が増える。長い会話履歴を全件 API に送ることで 1 回のリクエストコストが急増する可能性。履歴の先頭 N 件のみ送る「コンテキストウィンドウ制限」の実装を推奨（最大 20 メッセージに制限する）。
* **既存 AIAssistPanel との UX 重複**: one-shot パネルとマルチターンサイドバーが並立することでユーザーが混乱する可能性。将来的な統合を検討。
* **外部依存**: なし（既存 `AIService` を流用）

## 9. 計測・成果指標

リリース後評価のため未定義。定性的には「ChatGPT / Claude.ai への別ウィンドウ往来がゼロになる」体験改善をもって成功とみなす。

## 10. 参考資料

* 類似 OSS: [Obsidian Copilot プラグイン](https://github.com/logancyang/obsidian-copilot) — Obsidian でのマルチターン AI チャット実装の参考
* Apple Developer: [SwiftUI ScrollView + ScrollViewReader](https://developer.apple.com/documentation/swiftui/scrollviewreader) — チャット履歴の最下部スクロール実装
* OpenAI Chat Completions API: [Messages array format](https://platform.openai.com/docs/api-reference/chat/create)
* 既存実装参考: `Sources/Views/AI/AIAssistPanel.swift`、`Sources/Services/AIService.swift`
