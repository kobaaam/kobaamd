---
linear: KMD-68
status: in-progress
created_at: 2026-05-09
author: kobaamd_implement_code
---

# [KB4] エディタから SQLite インデックスを消費

## 1. 背景・目的

KB3（KMD-56〜62）で計画された SQLite + FTS5 + BM25 ベースの検索基盤を、kobaamd エディタの全文検索からも使えるようにする。現状の `SearchViewModel` は全ファイル走査の grep 実装で、1000 記事規模の vault では数秒〜数十秒かかる。本 issue では Swift 側で FTS5 インデックスを構築・読み出しすることで、100ms 以内の高速検索を実現する。

**重要な前提**: KB3 の `scripts/wiki/ingest.sh`（KMD-58）は未着手のため、本 issue では Swift 側で SQLite FTS5 インデックスを **読み書き両方** 実装する。後続の KMD-58 が同じスキーマを採用する想定。

## 2. ターゲットユーザーとユースケース

- 大規模 vault（数百〜数千記事）を運用するユーザーが、サイドバー検索で素早くヒットを得たい場面
- 既存の grep 検索しかなかったユーザーが、フォールバックで違和感なく使い続けられるよう、初回 vault 起動時はバックグラウンドでインデックス化が走る

## 3. 機能要件

### 必須要件
- vault 起動時（`workspaceRootChanged` 通知）に Swift 側でバックグラウンドインデックス化を起動
- インデックスは vault root 直下の `.kobaamd/index.sqlite`（vault 内に隔離。`.gitignore` 推奨だが本 issue では強制しない）に保存
- SQLite FTS5（contentless or external content）テーブル `articles_fts` にタイトル・本文を投入
- 検索クエリは BM25 ランクで降順ソート
- 検索結果は `[ファイル名 / 行番号 or スニペット]` で表示
- インデックス未構築 / 失敗時は既存 grep 検索（`SearchViewModel`）にフォールバック
- パフォーマンス: 1000 記事の vault で 100ms 以内に結果表示（インデックス利用時）

### オプション要件
- インクリメンタル更新（ファイル変更時の差分インデックス化）— 本 issue ではフルリビルドで OK
- snippet ハイライト（FTS5 `snippet()` 関数）

## 4. 非機能要件

- パフォーマンス: 1000 記事インデックス化 < 10 秒、検索 < 100ms
- アクセシビリティ: 既存の `SearchView` を維持
- macOS との整合性: macOS 14+ 同梱の `libsqlite3` を直接 import（C bridging）。外部依存追加なし

## 5. UI/UX

既存 `SearchView` を維持。検索結果に matchLine（grep 互換）を表示。スニペット拡張は将来。

```
+--------+
| 🔍 ... |
| Search |
+--------+
| File   |
| L42    |
| ...    |
+--------+
```

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] vault 開いた直後に `WikiIndexService` がバックグラウンドでインデックス化を開始する
- [ ] FTS5 テーブルが BM25 ランクで結果を返す
- [ ] 検索結果が記事のスニペット（または該当行）付きで表示される
- [ ] 1000 記事規模の vault で 100ms 以内に結果が表示される（手動確認 or perf log）
- [ ] インデックス未構築・破損時は grep 検索に自動フォールバックする
- [ ] swift build / swift test 通過

## 7. テスト戦略

- 単体テスト: `WikiIndexServiceTests` — 一時ディレクトリに数件のファイルを置いてインデックス化 → 検索 → 結果検証
- 手動確認: 実 vault で索引化後の検索体感
- フォールバック: DB ファイル削除後に検索が grep に戻ること

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Services/WikiIndexService.swift` | 追加 | SQLite FTS5 のインデックス化 + 検索 |
| `Sources/ViewModels/SearchViewModel.swift` | 変更 | WikiIndexService を優先利用、失敗時は既存 grep フォールバック |
| `Sources/App/AppViewModel.swift` or `Sources/Views/MainWindowView.swift` | 変更（最小） | `workspaceRootChanged` を購読してインデックス化を起動（既存の購読箇所がある場合はそこに相乗り、なければ最小エントリポイントを追加） |

**共有コンテナへの注意**:
- `SearchViewModel` を使う他機能: `SearchView` のみ。安全
- 変更してはいけない箇所:
  - `SearchView` の UI（既存 grep 互換結果表示を維持）
  - `FileService.supportedExtensions` 等の共有ロジック
  - 他 ViewModel（FileTree / Outline / Tags / QuickOpen など）に副作用を持ち込まない
  - Package.swift の dependencies 配列を変更しない（libsqlite3 は system shared library を直接 import）

### その他リスク
- libsqlite3 は macOS 14 同梱（バージョン 3.43+）。FTS5 はビルド時オプションで有効化されているはずだが、未有効環境ではインデックス作成時に SQL エラーになる → catch して grep フォールバック
- DB スキーマは KMD-57 と未調整。本 issue で先行決定する: `articles(id INTEGER PK, path TEXT UNIQUE, title TEXT, mtime REAL)` + `articles_fts(title, body, content='articles', content_rowid='id')`. KMD-58 着手時にこのスキーマを採用するか再評価する
- 競合: 同一 vault を複数ウィンドウで開いた場合の DB lock。SQLite の WAL モードを有効化して緩和

### 外部依存
- `import SQLite3`（システムフレームワーク。Package.swift 変更不要）

## 9. 計測・成果指標
- 1000 記事 vault での検索応答時間
- インデックス再構築失敗率（フォールバック発動率）

## 10. 参考資料
- SQLite FTS5: https://www.sqlite.org/fts5.html
- 関連: KMD-56 (KB3), KMD-57 (FTS5 スキーマ), KMD-58 (ingest スクリプト)

## 11. Gemini 調査ログ

<details>
<summary>Gemini 調査ログ（create_prd / review_prd 共有 — クリックで展開）</summary>

（本 PRD は implement_code が直接作成したため、Gemini 調査は未実施。スキーマ等は SQLite 公式ドキュメントベース）

</details>
