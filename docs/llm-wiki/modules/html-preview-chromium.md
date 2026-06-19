---
title: "HTML Preview via External Chromium"
slug: html-preview-chromium
type: module
updated_commit: 9003279c32f55577d2831c49edc18db76a435307
updated_at: 2026-06-19
freshness: current
sources:
  - path: Sources/Services/Preview/ChromiumPreviewController.swift
    sha: 726e11a14b9e7e1e55ed9cdb4fd918b6f535f7cb
  - path: Sources/Services/Preview/WorkspacePreviewHTTPServer.swift
    sha: 439445f2b93f52f440a42ef7897a7f825c85e42e
  - path: Sources/Views/Preview/HTMLPreviewView.swift
    sha: bd5e75654cf4496b2b00c732466344fbd0a3435c
---

# HTML Preview via External Chromium

## Overview

HTML ファイルの **Rendered** タブは、埋め込み CEF ではなく **外部 Chromium 系ブラウザ**（Google Chrome / Chromium / Brave 等）を `--app=` モードで起動して表示する。ワークスペースは loopback HTTP サーバ経由で配信し、相対パスの CSS/JS を Chrome と同じセマンティクスで解決する。

## Key Components

| コンポーネント | 責務 |
|----------------|------|
| `WorkspacePreviewHTTPServer` | `NWListener` で localhost にワークスペースを配信 |
| `ChromiumBrowserLocator` | インストール済み Chromium 系ブラウザを検出 |
| `ChromiumPreviewController` | `--app=` 起動・ウィンドウ位置合わせ・reload/navigate |
| `HTMLPreviewView` | Rendered タブ UI。設定で WebKit フォールバック可 |

プレビュー用スワップファイル `.kobaamd-preview.html` はファイルツリー・インデックスから除外される。

## Flows

1. ユーザーが HTML の Rendered タブを開く
2. `WorkspacePreviewHTTPServer.ensureStarted()` でポート取得、`setServeRoot(workspaceRoot)`
3. `http://127.0.0.1:<port>/...` を `ChromiumPreviewController.openOrNavigate` に渡す
4. 外部ブラウザがアプリウィンドウ横にリサイズ配置される
5. ファイル保存時は swap ファイル更新 → HTTP 経由で reload

## Invariants & Gotchas

- CEF 埋め込みは採用しない（メモリ・配布コストのため）
- ブラウザ未インストール時は WebKit プレビューにフォールバック
- プレビュー HTTP サーバはユーザーデータではなくワークスペースルートを serve する

## Recent Changes

- **v0.4.5**: Chromium + localhost 方式を本番採用（PR #161）

## Sources

- `Sources/Services/Preview/ChromiumPreviewController.swift`
- `Sources/Services/Preview/WorkspacePreviewHTTPServer.swift`
- `Sources/Views/Preview/HTMLPreviewView.swift`