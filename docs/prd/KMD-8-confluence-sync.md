---
linear: KMD-8
status: in-progress
created_at: 2026-04-27
author: kobaamd_implement_code
---

# Confluence 同期

## 1. 背景・目的

kobaamd のビジョンは「AI が生成した Markdown を Mac で最も快適に扱えるエディタ」である。AI が生成したドキュメントの最終的な届け先として、チームの知識管理基盤である Confluence が使われているケースは多い。現状 kobaamd はローカルファイルの編集・プレビューに特化しており、作成した Markdown を Confluence に投稿するには手動でコピー&ペーストするか、別ツールを経由する必要がある。

この機能により「kobaamd で書いて、Confluence に届ける」という一気通貫フローが実現し、AI 生成 Markdown の活用範囲を個人作業からチーム共有まで広げる。

---

## 2. ターゲットユーザーとユースケース

### ペルソナ A — ドキュメントエンジニア（個人利用・チーム共有）

kobaamd で設計書・仕様書・会議メモを書き、チームメンバーが参照する Confluence スペースに同期したい。

**シナリオ:**
1. 新しい `.md` ファイルを kobaamd で作成・編集する。
2. ファイルに対して Confluence ページ（スペース・親ページ）を 1 回設定する。
3. ⌘Shift+U（または「Confluence に同期」ボタン）を押すと Markdown → Confluence Storage Format に変換してページが作成または更新される。

### ペルソナ B — プロジェクトマネージャー

AI アシスト（⌘E）で生成した週次レポートをそのまま Confluence の定例ページに上書きしたい。

---

## 3. 機能要件

### 必須要件

- **3-1. Confluence 接続設定**: Confluence Cloud の Base URL・メールアドレス・API Token を設定画面（⌘,）に追加する。接続テストボタンを設け、成功/失敗をインラインで表示する。認証情報は `APIKeyStore` を拡張し macOS Keychain に保存する。
- **3-2. ページ同期設定（ファイル単位）**: 現在開いているファイルに対して「Confluence ページ設定」を行えるシートを設ける。設定項目: Space Key（例: `ENG`）、Parent Page ID（省略可）、Page Title。設定情報はファイル URL をキーとした JSON ファイル（`~/.config/kobaamd/confluence_mappings.json`）に永続化する。
- **3-3. 同期実行**: メニュー「File > Confluence に同期」（ショートカット: ⌘Shift+U）を追加する。Markdown を Confluence Storage Format（XHTML ベース）に変換して PUT/POST する。既存ページが存在する場合は `version.number` をインクリメントして上書き更新。存在しない場合は新規ページを作成し、取得した Page ID を `confluence_mappings.json` に書き戻す。
- **3-4. 同期結果フィードバック**: 同期成功時はステータスバーに「Confluence に同期しました (HH:MM)」と 3 秒間表示する。同期失敗時は `AppError` 経由でエラーシートを表示する。

### オプション要件

- **3-5. 自動同期（オートセーブ連動）**: 設定で「保存時に自動同期」を有効化できる。デフォルト OFF。

---

## 4. 非機能要件

- **パフォーマンス**: 同期 API 呼び出しはバックグラウンドスレッドで実行し、UI をブロックしない（`async/await` + `Task`）。
- **アクセシビリティ**: 設定シートとページ設定シートは VoiceOver でフォーカス可能な標準 SwiftUI コントロールのみ使用する。
- **macOS との整合性**: API Token は `SecItem` API 経由の Keychain に保存し、プレーンテキストで保存しない。

---

## 5. UI/UX

### 5-1. 設定画面への追加

```
+--[ 設定 (⌘,) ]----------------------------------------------+
|  Section: AI プロバイダー                                      |
|    OpenAI API Key:    [sk-...              ]                  |
|    Anthropic API Key: [sk-ant-...          ]                  |
|  ----------------------------------------------------------   |
|  Section: Confluence                                          |
|    Base URL:    [ https://yoursite.atlassian.net ]           |
|    Email:       [ user@example.com              ]           |
|    API Token:   [ ****************************  ]           |
|    [接続テスト]  成功: "接続OK (2026-04-25)"                  |
|  ----------------------------------------------------------   |
|  [ 保存 ]                                                     |
+-------------------------------------------------------------+
```

### 5-2. ページ設定シート

```
+--[ Confluence ページ設定 ]-------------------+
|  対象ファイル: design-spec.md               |
|  Space Key:  [ ENG        ]                |
|  Parent Page ID: [ 123456 ] (省略可)        |
|  Page Title: [ 設計仕様書 v1.0           ]  |
|  Page ID (既存): --- (未同期)              |
|  [ キャンセル ]              [ 保存 ]       |
+--------------------------------------------+
```

### 5-3. 同期ステータス表示（ステータスバー）

```
|  ...  42行 / 310語  |  Confluence: 同期済み (14:32)  |
```

---

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] **AC-1:** SettingsView（⌘,）に Confluence セクション（Base URL / Email / API Token / 接続テストボタン）が表示される。接続テストボタンを押すと Confluence REST API `/wiki/rest/api/space` を叩いて成功時に "接続OK" ラベルが表示される。
- [ ] **AC-2:** 「File > Confluence ページ設定...」でシートが開き、Space Key・Parent Page ID（省略可）・Page Title を入力して保存すると `~/.config/kobaamd/confluence_mappings.json` にそのファイルのマッピングが書き込まれる。
- [ ] **AC-3:** マッピング設定済みのファイルを開いた状態で ⌘Shift+U を押すと、Confluence REST API (`/wiki/rest/api/content`) に PUT/POST が発行され、ステータスバーに「Confluence に同期しました (HH:MM)」が 3 秒間表示される。
- [ ] **AC-4:** API Token が未設定の状態で ⌘Shift+U を実行すると、既存の `AppError` フローを通じてエラーシートが表示される（アプリがクラッシュしない）。
- [ ] **AC-5:** マッピング未設定のファイルで ⌘Shift+U を実行すると、先にページ設定シートへ誘導するダイアログが表示される。
- [ ] **AC-6:** 認証情報（API Token）は Keychain に保存され、UserDefaults や plist には平文で保存されていない。

---

## 7. テスト戦略

### 単体テスト対象

- `Sources/Services/ConfluenceService.swift`: `convertMarkdownToStorageFormat(_:)` 変換ロジック、ペイロード生成、HTTP メソッド選択ロジック
- `Sources/Services/APIKeyStore.swift`: `Provider.confluence` を追加した際の Keychain 読み書きテスト
- `Sources/ViewModels/ConfluenceSyncViewModel.swift`: `performSync()` のモック検証、`statusMessage` のタイムスタンプ検証

### 手動確認

1. 接続テストが実際の Confluence Cloud テナントに対して成功・失敗両方のケースで正しく表示されるか。
2. 新規ページ作成後に再度同期すると「上書き」になり Confluence 上にページが増殖しないか。
3. ネットワークオフライン状態で同期を実行した場合にエラーシートが表示されるか。

---

## 8. 想定リスク・依存

### 影響範囲マップ
<!-- 実装前に確認済み (2026-04-27) -->

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Services/ConfluenceService.swift` | 新規追加 | Markdown → Storage Format 変換 + REST API 呼び出し |
| `Sources/ViewModels/ConfluenceSyncViewModel.swift` | 新規追加 | 同期状態管理・UI バインディング |
| `Sources/Views/Settings/ConfluencePageSettingSheet.swift` | 新規追加 | ページ設定シート UI |
| `Sources/Services/APIKeyStore.swift` | 変更 | `Provider` enum に `.confluence` を追加 |
| `Sources/Views/Settings/SettingsView.swift` | 変更 | Confluence セクションを追加 |
| `Sources/App/AppCommand.swift` | 変更 | `confluenceSync` / `confluencePageSettings` コマンドを追加 |
| `Sources/Views/MainWindowView.swift` | 変更 | ステータスバーに同期ステータス表示・Notification 受信追加 |
| `Sources/App/AppViewModel.swift` | 変更 | `ConfluenceSyncViewModel` インスタンス保持、同期コマンド委譲 |
| `Sources/App/kobaamdApp.swift` | 変更 | File メニューへのコマンド追加 |
| `Sources/Services/AIService.swift` | 変更 | `complete()` メソッドの switch 文に `default` ケースを追加（APIKeyStore.Provider の新ケース追加によるコンパイルエラー回避のために必要） |
| `Package.swift` | 変更なし | 外部依存追加なし（swift-markdown を流用） |

**共有コンテナへの注意:**

- `MainWindowView.swift` は TabBar / Split / Editor / Sidebar など複数機能が同居するファイル。ステータスバー (`StatusCommandBar`) のみ変更し、他の部分は一切触れない。
- `AppViewModel.swift` はタブ管理・AI補完・PDF書き出しなど多機能が同居。`ConfluenceSyncViewModel` の保持追加と同期デリゲートのみ変更し、既存タブ・AI・PDF ロジックは一切変更しない。
- `APIKeyStore.swift` は既存 `.openai` / `.anthropic` の switch 文すべてを網羅的に更新が必要（コンパイラが漏れを検出）。

**変更してはいけない箇所:**
- `AppViewModel` の既存タブ管理ロジック（`openInTab`, `switchToTab`, `closeTab`, `flushActiveTab`, `activate`）
- `AppViewModel` の AI インライン補完ロジック（`startAIInlineCompletion`）
- `AppViewModel` の PDF 書き出しロジック（`exportPDF`, `handlePDFExportResult`）
- `APIKeyStore` の既存 `.openai` / `.anthropic` の Keychain save/load/clear ロジック
- `SettingsView` の既存 AI プロバイダーセクション・Formatting セクション・保存ボタン
- `AppCommand.swift` の既存コマンド（`save`, `newFile`, `find`, `openFolder`, `aiAssist`, `toggleSidebar`, `newTab`, `formatDocument`, `exportPDF`, `quickOpen`）
- `kobaamdApp.swift` の既存メニュー項目・SettingsView の WindowGroup

### その他リスク

- Confluence Storage Format の変換は swift-markdown の AST ウォーカーを使いカスタム実装する（外部依存追加なし）
- Confluence Cloud API のレート制限: 300 req/min（問題なし）
- Mermaid ブロックは v1 では `<pre>` として変換（Storage Format のマクロ対応は v2）

---

## 9. 計測・成果指標

kobaamd はオフライン優先・シンプル設計のためテレメトリーを外部送信しない。

---

## 10. 参考資料

- Confluence Cloud REST API v1: https://developer.atlassian.com/cloud/confluence/rest/v1/api-group-content/
- Confluence Storage Format (XHTML): https://confluence.atlassian.com/doc/confluence-storage-format-790796544.html
- API Token 発行方法: https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/
- mark (Go): https://github.com/kovetskiy/mark
