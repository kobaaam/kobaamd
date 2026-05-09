---
linear: KMD-69
status: in-progress
created_at: 2026-05-09
author: kobaamd_implement_code (Opus)
---

# [KB4] kobaamd MCP server で vault を外部 LLM に公開

## 1. 背景・目的

Clearly が `clearly mcp` で vault を外部 AI (Claude Desktop / Cursor) に公開しているのと同等の機能を kobaamd にも持たせる。これにより外部 LLM クライアントから kobaamd vault（Markdown ノート群）を読み取り検索できるようになり、KB4「kobaamd 自身を knowledge base 化する」一連 (KMD-65 Backlinks / KMD-66 Tags / KMD-67 Frontmatter / KMD-68 SQLite Index) の集大成になる。

## 2. ターゲットユーザーとユースケース

- ユーザー: Claude Desktop / Cursor / Claude Code を併用するエンドユーザー
- ユースケース 1: Claude Desktop で `search_notes("Mermaid 設定")` と問いかけると kobaamd の SQLite FTS5 インデックスを検索して該当ノートをスニペット付きで返す
- ユースケース 2: Cursor から `read_note("path")` で個別ノート全文を読み込み、AI コーディング中の補助知識として参照する

## 3. 機能要件

### 必須要件
- `kobaamd mcp <vault-root>` サブコマンドで stdio MCP server を起動
  - 引数 `<vault-root>` は vault のルートディレクトリ絶対パス（必須）。省略時は exit 2（usage エラー）
- MCP プロトコル準拠（JSON-RPC 2.0 over stdio、`initialize` / `tools/list` / `tools/call` をサポート）
- 6 つの読み取り専用ツールを公開:
  1. `search_notes(query: string, limit?: int=20)` — SQLite FTS5 で BM25 検索、結果を `[{path, title, snippet, rank}]` で返す
  2. `read_note(path: string, range?: {startLine: int, endLine: int})` — ノート全文 + frontmatter + 見出しを返す
  3. `list_notes(under?: string)` — vault 内の Markdown ファイル一覧（path のリスト）
  4. `get_headings(path: string)` — 指定ノートの見出しアウトライン（`[{level, text, line}]`）
  5. `get_backlinks(path: string)` — linked + unlinked mentions（`[{sourcePath, line, snippet, kind}]`）
  6. `get_tags(tag?: string)` — `tag` 未指定: 全タグ + frequency / 指定時: そのタグを持つノート path のリスト
- 各ツールの `inputSchema` を JSON Schema として宣言（`tools/list` レスポンスに含める）
- `protocolVersion: "2025-06-18"` 以降を返す（互換のため `2024-11-05` も許容）
- vault ルート外のファイルアクセスを禁止（path traversal 対策: `..` / 絶対パス検証）

### オプション要件
- 起動時のログを `stderr` に出力（`stdout` は MCP プロトコル専用）
- 不正リクエスト時は JSON-RPC 2.0 エラーオブジェクト形式で返す（`-32600` 等）

## 4. 非機能要件

- パフォーマンス: search_notes は SQLite インデックスが既に構築済みの前提で 100ms 以内（既存 KMD-68 の WikiIndexService 流用）
- セキュリティ: 書き込みツールは公開しない（読み取り専用 MVP）。vault ルート外アクセス禁止
- macOS との整合性: macOS 14+ / Swift 5.9（既存 Package.swift 維持）
- 依存追加なし（Foundation のみで JSON-RPC 2.0 over stdio を実装。理由は Section 8 参照）

## 5. UI/UX

CLI なので UI なし。クライアント側の `mcp.json` 設定例を `docs/mcp-setup.md` に追加。

```jsonc
// ~/Library/Application Support/Claude/claude_desktop_config.json
{
  "mcpServers": {
    "kobaamd": {
      "command": "/Applications/kobaamd.app/Contents/MacOS/kobaamd",
      "args": ["mcp", "/Users/me/Documents/MyVault"]
    }
  }
}
```

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `kobaamd mcp <vault-root>` で stdio MCP server が起動する（無引数 GUI 起動に影響なし）
- [ ] `initialize` リクエストに `serverInfo` / `capabilities.tools` を含む応答を返す
- [ ] `tools/list` で 6 ツールが JSON Schema 付きで返る
- [ ] `tools/call` で各ツールが期待値を返す（最低 search_notes / read_note / list_notes は手動 echo テストで動作確認）
- [ ] vault ルート外への path traversal が拒否される（エラーで応答）
- [ ] `swift build` が成功
- [ ] `swift test` で既存テストが pass
- [ ] 新規ユニットテスト: 各ツールの引数バリデーション + path traversal 防止
- [ ] `docs/mcp-setup.md` が追加され、Claude Desktop / Cursor 用設定例とトラブルシュートが記載される

## 7. テスト戦略

- 単体テスト:
  - `Tests/MCPServerTests.swift`（新規）: JSON-RPC リクエスト/レスポンスの round-trip、各 tool の引数バリデーション、path traversal 拒否
  - 既存 `WikiIndexService` / `BacklinksScanner` / `Frontmatter` のテストは既存維持
- 手動確認:
  - `swift run kobaamd mcp /tmp/test-vault` で起動 → `{"jsonrpc":"2.0","id":1,"method":"initialize",...}` を echo して応答 JSON を観測
  - Claude Desktop の `mcp.json` に登録 → 「○○ノートを検索して」で動作確認

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/App/kobaamdApp.swift` | 変更 | `@main` を `kobaamdApp` から `KobaamdEntryPoint` (新規) に切り替え。`mcp` サブコマンド時は MCP モード、それ以外（無引数 / Finder open）は従来 SwiftUI App.main() 経由で起動 |
| `Sources/CLI/MCPEntryPoint.swift` | 追加 | 新規 `@main` エントリポイント。CommandLine.arguments を解析して MCP モード / GUI モードを分岐 |
| `Sources/CLI/MCPServer.swift` | 追加 | JSON-RPC 2.0 over stdio のメインループ + ツールディスパッチ |
| `Sources/CLI/MCPProtocol.swift` | 追加 | JSON-RPC 2.0 リクエスト/レスポンス型 (Codable + JSON Schema 構造体) |
| `Sources/CLI/Tools/MCPToolRegistry.swift` | 追加 | 6 ツールの登録・スキーマ定義 |
| `Sources/CLI/Tools/SearchNotesTool.swift` | 追加 | SQLite WikiIndexService をシン化したスタンドアロン検索 |
| `Sources/CLI/Tools/ReadNoteTool.swift` | 追加 | frontmatter + body + headings 統合 |
| `Sources/CLI/Tools/ListNotesTool.swift` | 追加 | vault 内 Markdown 列挙 |
| `Sources/CLI/Tools/GetHeadingsTool.swift` | 追加 | 既存 OutlineParser ロジック流用（簡易版を CLI 内に）|
| `Sources/CLI/Tools/GetBacklinksTool.swift` | 追加 | BacklinksScanner を呼ぶ |
| `Sources/CLI/Tools/GetTagsTool.swift` | 追加 | Frontmatter.parse でタグを抽出 |
| `Sources/CLI/VaultPath.swift` | 追加 | path traversal バリデーション |
| `Tests/MCPServerTests.swift` | 追加 | round-trip + 引数バリデーション + path traversal 防止 |
| `docs/mcp-setup.md` | 追加 | Claude Desktop / Cursor 設定例 |
| `Package.swift` | **変更しない** | 依存追加なし（Foundation のみ）|

**共有コンテナへの注意**:

- `Sources/App/kobaamdApp.swift` を変更するが、**SwiftUI Scene 構造 (WindowGroup / Settings / Help) は一切変更しない**。`@main` 属性のみ移動して `KobaamdEntryPoint` から `kobaamdApp().main()` 相当を呼ぶ
- 既存 ViewModel / Service / View ファイルには一切手を入れない（CLI 専用ロジックは `Sources/CLI/` 配下に閉じる）
- `BacklinksScanner` は @MainActor 不要の Sendable struct なので CLI からも呼べる。`WikiIndexService` は `@MainActor` クラスなので CLI からは呼ばず、CLI 用に SQLite アクセスを別途実装する（コードを最小限に複製、共通テンプレ抽出は将来）
- 既存テスト (`Tests/*.swift`) は触らない

**変更してはいけない箇所**:

- `Sources/Views/**/*` 全て（SwiftUI レイヤーは MCP と無関係）
- `Sources/ViewModels/**/*` 全て
- `Sources/Services/WikiIndexService.swift`（@MainActor のため CLI からアクセス不可、別途 SQLite アクセスを CLI 用に実装するため触らない）
- `Sources/Services/BacklinksScanner.swift`（Sendable のまま流用するだけ）
- `Sources/Models/Frontmatter.swift`（流用するだけ）
- `Sources/App/AppCommand.swift` / `Notification.Name` 拡張（MCP は GUI と無関係）
- `Package.swift` の dependencies / target 設定（依存追加なし）
- 既存の `kobaamdApp` 構造体本体（ファイル名は変えず、`@main` 属性だけ取り外して別ファイルから呼び出される形にする）

### その他リスク

- **互換性**: `@main` 属性の付け替えで Finder ダブルクリック / `open kobaamd.app` の起動経路が壊れないか要検証。`KobaamdEntryPoint.main()` が **引数なし** の場合は `kobaamdApp.main()` を呼ぶことで従来動作を維持
- **MCP プロトコル**: 仕様 2025-06-18 に準拠。クライアントが古い 2024-11-05 を要求してきたら同等応答を返す
- **将来の依存追加**: 公式 swift-sdk が Swift 6.0+ を要求するため、Package.swift をメジャー上げするタイミング（別 issue）でリプレースする
- **書き込みツール**: 将来 (KMD-69-followup) で追加。読み取り専用 MVP

## 9. 計測・成果指標

- Claude Desktop から `search_notes` / `read_note` が実際に呼べることを動作確認スクショで証明
- 6 ツールの `tools/list` 出力（JSON Schema）が手元 echo テストで取れる

## 10. 参考資料

- MCP 仕様: <https://modelcontextprotocol.io/specification/2025-06-18>
- Clearly mcp: 同等先行事例
- 既存実装: `Sources/Services/WikiIndexService.swift`、`BacklinksScanner.swift`、`Models/Frontmatter.swift`

## 11. Gemini 調査ログ

<details>
<summary>Gemini 調査ログ（create_prd / review_prd 共有 — クリックで展開）</summary>

### Entry 1
- **timestamp**: 2026-05-09T14:00:00+0900
- **agent**: kobaamd_create_prd（implement_code から代行）
- **model**: gemini-3.1-pro-preview
- **topic**: B. 技術実装リサーチ
- **prompt**:
  ```
  現時点 (2026-05) で macOS Swift から MCP (Model Context Protocol) server を stdio で実装する
  ために最も使われている公式・準公式ライブラリを教えて。

  知りたいこと:
  1. Package URL
  2. 最低 Swift / macOS バージョン
  3. stdio MCP server の最小サンプルコード
  4. tool input の JSON Schema 宣言の書き方
  5. tool 出力の返し方
  6. async/await サポートの有無
  7. 完全なエントリポイント例
  ```
- **response**:
  ```
  Anthropic 等の公式・準公式オーガナイゼーションから Swift 専用の MCP SDK は提供されていない。
  事実上の標準は Foundation のみで JSON-RPC 2.0 over stdio をネイティブ実装。
  Swift 5.9+ macOS 14+ で動作。FileHandle.standardInput.bytes.lines を使う非同期ループで
  initialize / tools/list / tools/call をハンドリング。Dictionary ベースで JSON Schema を宣言。
  Structured Text ({content: [{type: text, text: ...}]}) で返す。
  fflush(stdout) でレスポンスを即座に flush する。
  ```
  実は modelcontextprotocol/swift-sdk が公式に存在するが Swift 6.0+ / Xcode 16+ を要求。
  本プロジェクト (Swift 5.9 / Package.swift swift-tools-version:5.9) では採用不可。
- **reflected_in**: Section 3 必須要件 / Section 4 非機能要件 / Section 8 影響範囲（依存追加なしの根拠）

</details>
