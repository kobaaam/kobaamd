# kobaamd MCP Setup

`kobaamd` は `mcp` サブコマンドで stdio MCP server を起動します。

## Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "kobaamd": {
      "command": "/Applications/kobaamd.app/Contents/MacOS/kobaamd",
      "args": ["mcp", "/Users/me/Documents/MyVault"]
    }
  }
}
```

## Cursor

`~/.cursor/mcp.json`

```json
{
  "mcpServers": {
    "kobaamd": {
      "command": "/Applications/kobaamd.app/Contents/MacOS/kobaamd",
      "args": ["mcp", "/Users/me/Documents/MyVault"]
    }
  }
}
```

## ローカル確認

```bash
swift run kobaamd mcp /tmp/test-vault
```

別ターミナルから:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | swift run kobaamd mcp /tmp/test-vault
```

## トラブルシュート

- `usage: kobaamd mcp <vault-root>`
  - vault root 引数が不足しています。
- `invalid vault root: /path/to/vault`
  - 指定パスが存在しないか、ディレクトリではありません。
- `Unknown tool: ...`
  - MCP クライアントが未実装の tool 名を呼んでいます。
- `Invalid params: missing path`
  - `read_note` / `get_headings` / `get_backlinks` に `path` がありません。
- `Invalid params: missing query`
  - `search_notes` に `query` がありません。
- `Error: The file doesn’t exist.`
  - 指定されたノートが vault 内に存在しません。
- `Error: The operation could not be completed. (kobaamd.VaultPath.Error outsideVault)`
  - `..` や vault 外の絶対パスが拒否されています。

## 注意

- `stdout` は MCP JSON-RPC 専用です。通常ログは `stderr` に出ます。
- 公開される tool は読み取り専用です。
- 対象ファイルは `.md` と `.markdown` のみです。
