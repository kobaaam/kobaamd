---
linear: KMD-191
status: backlog
created_at: 2026-05-10
author: Claude Opus (main session)
---

# エディタのスクロール / ファイル切替時の loading 体感を抜本改善（5レイヤー）

## 1. 背景・目的

KMD-184 で md スクロール中の loading 頻発は一旦解消したが、その後ユーザー（オーナー）から「ファイル切替直後にスクロールしようとすると 2〜3秒間カクつく / ロックされたように感じる」との継続フィードバックを受領。さらに `os.Logger` ベースの `PerfLogger` で実測したところ、シェル HTML ビルド・SwiftUI observation graph 差分計算・WKWebView スクロール同期 IPC・Backlinks スキャン・ファイル列挙の attribute prefetch という **5つの独立したボトルネック** が確認された。

「軽量な Markdown エディタ」というプロダクトビジョンを毀損する致命的 UX 課題なので、まとめて修正する。

## 2. ターゲットユーザーとユースケース

- 9000+ ファイル規模の vault（Obsidian 互換ワークスペース）を扱うパワーユーザー
- ファイル切替を高頻度で繰り返すユーザー（タブ切替・サイドバー操作・grep ジャンプ）
- 大きい md ファイル（数千行）を編集しながらプレビューを参照するユーザー

## 3. 機能要件

- **必須要件**:
  - ファイル切替後 0.2 秒以内にスクロール可能（実測値）
  - スクロール中に loading インジケータが頻発しない
  - 大きいファイル（10000 行）でもスクロール 60fps を維持
- **オプション要件**:
  - 連続したファイル切替で Backlinks 列挙を再実行しない（cache hit）

## 4. 非機能要件

- **パフォーマンス**:
  - shell HTML build: 8.7s → < 10ms
  - SwiftUI observation diff: 7.94s → < 50ms
  - updateNSView spam: 50+/sec → 0/sec idle
  - Backlinks scanWorkspace: 11.8s → < 3s 初回 / < 100ms cache hit 時
  - File enumeration: 1.65s → 0ms cache hit 時
- **メモリ**: 既存ベースライン +10MB 以内
- **macOS との整合性**: NSTextView / WKWebView / Notification Center の標準 API のみ使用

## 5. 修正の全体像（5レイヤー）

```
[ファイル切替]
    │
    ├─① PerfLogger 強化（NSLog → os.Logger）
    │   └─ log show --predicate 'subsystem == "com.kobaamd.app"' で実測
    │
    ├─② MarkdownService 高速化
    │   ├─ shellHead テーマ別キャッシュ（mermaid.min.js 3MB を再生成しない）
    │   └─ toHTML(text:body:) で body 再利用（二重 markdown parse 回避）
    │
    ├─③ PreviewViewModel SwiftUI 最適化
    │   ├─ shellHTML を @ObservationIgnored 化（3MB 文字列を observation graph から除外）
    │   ├─ shellVersion: Int で変更通知（軽量）
    │   └─ updateImmediate でファイル切替時 debounce 飛ばし即時 render
    │
    ├─④ MarkdownWebView IPC 削減
    │   ├─ ScrollSyncDebouncer（leading + trailing 16ms throttle）
    │   ├─ NotificationCenter ベース scroll sync（observation graph 経由廃止）
    │   └─ shellVersion: Int で 3MB 文字列比較を整数比較に
    │
    └─⑤ BacklinksViewModel 体感最適化
        ├─ 初期 debounce 150ms → 800ms（ファイル切替直後はエディタ・プレビュー優先）
        ├─ Task.detached(.utility)（編集体験を圧迫しない優先度）
        ├─ withTaskGroup 並列読み込み（最大 8 並列）
        ├─ FileManager.enumerator の attribute prefetch（.isRegularFileKey）を停止
        └─ folder set ベースのファイル一覧キャッシュ（連続ファイル切替で再列挙不要）
```

## 6. 受け入れ条件 (Acceptance Criteria)

- [x] PerfLogger が `os.Logger` ベースで `log stream --predicate 'subsystem == "com.kobaamd.app"'` から拾える
- [x] 9000+ ファイル workspace でファイル切替直後（< 200ms）からスクロールが反応する
- [x] shell HTML 生成が 2 回目以降 < 10ms（テーマキャッシュ）
- [x] SwiftUI observation graph 経由で 3MB の shellHTML が diff されない
- [x] updateNSView がアイドル時に発火しない（NotificationCenter 経由）
- [x] Backlinks ファイル列挙が 2 回目以降 cache hit する（`source=cache` がログに出る）
- [x] ScrollSyncDebouncerTests が pass

## 7. テスト戦略

- **単体テスト**: `Tests/kobaamdTests/ScrollSyncDebouncerTests.swift`（新規） — leading + trailing throttle 動作・separated updates の挙動を検証
- **手動確認**: 9000+ ファイルの実 vault で連続ファイル切替してスクロール体感確認 + `log show` でメトリクス確認
- **swift build / swift test**: `kobaamd_validate_build` 経由

## 8. 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Diagnostics/PerfLogger.swift` | 変更 | NSLog → os.Logger |
| `Sources/Services/MarkdownService.swift` | 変更 | shellHead cache + toHTML(body:) overload |
| `Sources/ViewModels/PreviewViewModel.swift` | 変更 | @ObservationIgnored + shellVersion + updateImmediate |
| `Sources/ViewModels/BacklinksViewModel.swift` | 変更 | debounce + parallel scan + cache + nil prefetch |
| `Sources/Views/Preview/MarkdownWebView.swift` | 変更 | ScrollSyncDebouncer + Notification ベース |
| `Sources/Views/Preview/PreviewView.swift` | 変更 | selectedFileURL onChange immediate render |
| `Sources/App/AppViewModel.swift` | 変更 | previewScrollRatio @ObservationIgnored + Notification |
| `Sources/App/kobaamdApp.swift` | 変更 | .previewScrollRatioChanged Notification.Name |
| `Sources/Views/Editor/EditorView.swift` | 変更 | setPreviewScrollRatio caller 更新 |
| `Sources/Views/Sidebar/OutlineView.swift` | 変更 | setPreviewScrollRatio caller 更新 |
| `Tests/kobaamdTests/ScrollSyncDebouncerTests.swift` | 追加 | ScrollSyncDebouncer の単体テスト |

**共有コンテナへの注意**:
- `MarkdownService.shellHeadCache` は static dictionary。テスト時のテーマ切替で壊れないよう、キーはテーマ ID 含む文字列にする
- `BacklinksViewModel.fileListCache` も static。folder set のキーで判定するので workspace 切替時も正しく invalidate される

### その他リスク
- **既存コードへの影響**: NotificationCenter 経由 scroll sync は Coordinator 寿命と連動。deinit で removeObserver 必須
- **互換性**: 公開 API 破壊なし。@Observable プロパティの追加・削除は SwiftUI の依存関係に影響するため `shellVersion` の `&+=` 演算でラップアラウンド対応
- **外部依存**: なし

## 9. 計測・成果指標

リリース後 1 週間でユーザーから「ファイル切替時のスクロールロック / loading 頻発」フィードバックがゼロになること。`os.Logger` 経由で再発を即検知できる体制が整った。

## 10. 参考資料

- KMD-184: md スクロール中の loading 頻発を解消（前段の修正）
- KMD-187: APIKeyStore in-process キャッシュ（誤診だった hop だが副次的に得た知見）
- Apple `os.Logger` ドキュメント
