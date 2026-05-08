---
linear: KMD-65
status: in-review
created_at: 2026-05-09
author: kobaamd_implement_code (Opus)
---

# [KB4] Backlinks ペインの実装

## 1. 背景・目的

kobaamd は AI が生成した Markdown を扱うエディタとして、知識ベース的な使い方も視野に入れている。Phase 4 KB4 として、Clearly の `get_backlinks` 相当の機能をサイドバーに組み込み、現在開いているファイルがどこから参照されているかを一覧する。

単純な文字列マッチでは false positive が多いため、`unlinked mentions`（明示リンクされていない言及）は Haiku ベースの文脈一致判定で絞り込む。CLAUDE.md に記載の Haiku 用途指針（短い構造化判定をバッチで回す + Prompt Caching 併用）に沿って実装する。

## 2. ターゲットユーザーとユースケース

- 知識ベースを Markdown で書いているユーザーが、ある記事を編集中に「この記事を引用している他の記事はどれか」を即座に把握したい
- `[[wikilink]]` を未だ書いていないが文中で言及されている関連記事を発見し、`Convert to link` で明示リンクに昇格させたい

## 3. 機能要件

**必須要件**:
- サイドバーに `BACKLINKS` セクションを追加し、現在のアクティブファイルへの linked references / unlinked mentions を表示する
- linked references: 機械的検出（正規表現で `[[basename]]` / `[[basename|alias]]` / `[[basename#heading]]` / `](basename.md)` / `](basename)` を検出）
- unlinked mentions: 機械的候補抽出（ファイル名 basename の本文出現、ただし linked references 範囲は除外）→ Haiku で文脈一致判定（YES/NO + 1 行理由）→ YES のみ採用
- 各 backlink にコンテキストスニペット（前後 30 文字）を付与
- クリックで該当ファイル + 該当行にジャンプ（既存の `.jumpToLine` Notification 経由）
- unlinked mention に `Convert to link` ボタン（マッチテキストを `[[basename]]` で書き換えて保存）
- Haiku 判定結果はキャッシュ（`(source content_hash, target basename, match offset)` キー）で再判定をスキップ

**オプション要件**:
- `BACKLINKS` 折りたたみ ON/OFF（既定: 展開）
- `BACKLINKS` セクションヘッダーに linked count + unlinked count バッジ
- ローディング中インジケータ
- API キー未設定時は linked references のみ表示し、unlinked mentions セクションは「Anthropic API キー未設定」と表示

## 4. 非機能要件

- **パフォーマンス**:
  - linked / unlinked 候補抽出は detached priority `.userInitiated` で実行
  - ファイル切り替え時は 500ms デバウンスして抽出を開始
  - Haiku 判定は同一ファイル内 batch（最大 10 件まで並列、`TaskGroup`）。それを超える候補があれば最初の 10 件で打ち切り（false positive 多発を避ける）
- **アクセシビリティ**:
  - VoiceOver で各行にファイル名・行番号・コンテキストを読み上げる
  - キーボードナビゲーション可（既存の List/ScrollView 範囲内）
- **macOS 整合性**:
  - 既存サイドバーの Section header / kobaamd 配色 (`Color.kobaSidebar` / `kobaInk` / `kobaMute` / `kobaAccent`) を踏襲
  - `Outline` セクションと同じ折りたたみ UX（`TODO` セクション風のヘッダ）
- **キャッシュ保存場所**: `~/Library/Caches/<bundleID>/backlinks-context-cache.json`（ファイルが破損した場合は丸ごと破棄して再構築）

## 5. UI/UX

```
+---- SIDEBAR ----+
| EXPLORER        |
| ├─ folder/      |
| └─ note.md      |
| ── (resize) ──  |
| OUTLINE         |
| H1 …            |
| ── (separator)──|
| ▾ BACKLINKS (3) |
|   LINKED (2)    |
|   ├ foo.md L5   |
|   │  ...note... |
|   └ bar.md L12  |
|      ...note... |
|   UNLINKED (1)  |
|   └ baz.md L7   |
|      ...note... |
|      [Convert]  |
| ── (separator)──|
| ▸ TODO          |
+-----------------+
```

行構造:
- `<filename>` (sm bold) + `L<line>` (mute2)
- next line: `…<前30字><match><後30字>…` (caption, mute, lineLimit 1)
- unlinked のみ末尾に `Convert to link` (capsule button, kobaAccent)

## 6. 受け入れ条件 (Acceptance Criteria)

- [ ] `BACKLINKS` セクションがサイドバーの OUTLINE 下、TODO 上に表示される
- [ ] linked references が `[[basename]]` 形式 / `]( ... )` 形式の両方で検出される
- [ ] unlinked mentions の候補抽出はファイル名 basename（拡張子除く）の本文一致で行われる
- [ ] Anthropic API キーが設定されていれば、unlinked 候補に Haiku の YES/NO 判定がかかり、YES のみ表示される
- [ ] API キー未設定時は linked references セクションのみ表示し、unlinked は「API キー未設定」プレースホルダ
- [ ] 各 backlink にクリック可能領域があり、タップで該当ファイル + 該当行にジャンプする
- [ ] `Convert to link` を押すと参照元ファイルの該当 mention が `[[basename]]` に置換され、ファイルが上書き保存される
- [ ] Haiku 判定結果がキャッシュされ、同一 (source content_hash, target basename, match offset) は再判定されない
- [ ] 既存の Outline / TODO / FileTree の振る舞いに退行が無い
- [ ] `swift build` が通る / 既存テストが通る / 新規ユニットテスト（mention scanner & cache）が通る

## 7. テスト戦略

**単体テスト** (新規):
- `BacklinksScannerTests`:
  - `[[basename]]` を linked として検出
  - `]( basename.md )` を linked として検出
  - basename の単純出現を unlinked 候補として検出
  - linked 範囲に重なる出現は unlinked から除外
  - コンテキストスニペットの前後 30 字抽出
- `BacklinkContextCacheTests`:
  - put / get の正常系
  - hash 不一致でキャッシュ miss
  - JSON のシリアライズ往復

**スナップショット**: なし（既存 Sidebar スナップショットは temporarily 影響を受ける可能性があるため、変更したら更新）

**手動確認**:
- 複数記事が basename を含む状態で linked/unlinked が分離表示されること
- `Convert to link` 後にディスク上のファイルが書き換わること
- API キー未設定時に linked のみ出ること

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Models/Backlink.swift` | 追加 | `Backlink` / `BacklinkKind`(`.linked` / `.unlinked`) / `BacklinkSection` モデル |
| `Sources/Services/BacklinksScanner.swift` | 追加 | ワークスペース横断スキャン（linked + unlinked 候補） |
| `Sources/Services/BacklinkContextChecker.swift` | 追加 | Haiku 呼び出し（Anthropic Messages API、JSON モード） |
| `Sources/Services/BacklinkContextCache.swift` | 追加 | `~/Library/Caches/<bundleID>/backlinks-context-cache.json` の load/save/get/put |
| `Sources/ViewModels/BacklinksViewModel.swift` | 追加 | `@Observable @MainActor`、debounced refresh、`convertToLink()` |
| `Sources/Views/Sidebar/BacklinksView.swift` | 追加 | UI（折りたたみ・linked/unlinked サブセクション・Convert ボタン） |
| `Sources/Views/Sidebar/SidebarView.swift` | 変更 | OUTLINE と TODO の間に `BACKLINKS` セクションを差し込む。OUTLINE / TODO のレイアウト計算を維持 |
| `Sources/App/AppViewModel.swift` | 変更 | `let backlinksViewModel = BacklinksViewModel()` を追加。`activate(tab:)` 内で URL 変更時に `backlinksViewModel.refresh(currentURL:, workspaceFolders:)` をトリガ |
| `Tests/kobaamdTests/BacklinksScannerTests.swift` | 追加 | basename matching / linked vs unlinked 振り分け |
| `Tests/kobaamdTests/BacklinkContextCacheTests.swift` | 追加 | キャッシュの put/get/hash mismatch |

**共有コンテナへの注意**:
- 対象ファイルを使っている他機能:
  - `SidebarView.swift`: EXPLORER（FileTree）/ OUTLINE / TODO の 3 機能が同居。`GeometryReader` 内で `availableHeight` を 3 領域で配分しており、新しい BACKLINKS セクションを足す際は同じ計算スタイルに合わせる
  - `AppViewModel.swift`: タブ管理 / AI / Outline / Todo / Confluence / QuickOpen など多数の状態を持つ。`activate(tab:)` のフックに 1 行追加するだけで他は触らない
- 変更してはいけない箇所:
  - `SidebarView.swift` の EXPLORER / OUTLINE / TODO 各セクションのレイアウト・ジェスチャ・既存のフック（`onReceive`, `onAppear`, `restoreWorkspace` 等）。新規追加は OUTLINE と TODO の間に折りたたみセクションを 1 つ差し込む形で行い、既存ハンドルや配色定数は変更しない
  - `AppViewModel.swift` の AI 系 / Tab 系 / save 系メソッドのシグネチャと内部ロジック
  - `OutlineViewModel` / `TodoViewModel` / `FileTreeViewModel` のロジック・公開 API
  - `AIService` / `APIKeyStore` / `FileService` の既存 API

### その他リスク
- **既存コードへの影響**: SidebarView のレイアウト計算（OUTLINE と TODO の `GeometryReader` 内のサイズ配分）が変わるため、OUTLINE / TODO の表示が retain されることを目視確認する
- **互換性**: 新規ファイルが大半。既存 UserDefaults / API は変更しない。新規キャッシュは `~/Library/Caches` 配下なのでアプリアップデート / クリアで安全に消える
- **外部依存**: 既存の `URLSession` / `APIKeyStore`（Anthropic キー） / `FileService` のみ。新規依存なし
- **Haiku 判定の信頼性**: false positive 抑制のため、Haiku のレスポンスを `YES` / `NO` で厳密パースし、それ以外は `unknown`（= 表示しない、キャッシュもしない）として扱う。リトライは 1 回まで

## 9. 計測・成果指標

- 任意。リリース後、`BacklinksView` の表示時間（debounce + scan + Haiku）の P95 を内部ログで観測できると望ましい

## 10. 参考資料

- Linear: https://linear.app/kobaan/issue/KMD-65/kb4-backlinks-ペインの実装
- Clearly `get_backlinks` (参照元): docs にリンクなし、issue 記述ベース
- CLAUDE.md「Haiku の用途定義」セクション
- 既存サイドバー実装: `Sources/Views/Sidebar/{SidebarView,OutlineView,TodoView,SearchView}.swift`
