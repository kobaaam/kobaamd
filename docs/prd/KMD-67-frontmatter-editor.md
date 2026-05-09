---
linear: KMD-67
status: in-review
created_at: 2026-05-09
author: kobaamd_rework_issue (Opus, after human feedback)
---

# [KB4] frontmatter 認識・編集 UI

## 1. 背景・目的

LLM Wiki / Knowledge Base パイプライン (KMD-45 系列、`kb-pipeline` ラベル) の一部として、Markdown ファイルの YAML frontmatter を構造化された UI で編集できるようにする。手書きでの YAML 構文ミスを防ぎ、KMD-66 で実装したタグ機能と互換性のある形でメタデータを管理する。

## 2. ターゲットユーザーとユースケース

- ノート作成者: title / tags / aliases / date / description を素早く編集
- LLM Wiki 投入: frontmatter のあるノートを安全に編集して再投入できる

## 3. 機能要件

- 必須要件:
  - エディタ上部に折りたたみ可能な frontmatter エディタを表示
  - 標準フィールド（title / category / tags / aliases / date / description）を構造化フォームで編集
  - 標準外フィールドは情報を失わずに保持（extraLines）
  - frontmatter なしのファイルでは「Add frontmatter」ボタン
  - YAML 構文エラー / ネスト dict 検出時は警告バナー
  - **書式保持**: 編集していないフィールドは元の YAML 表現（inline list / block list / quoted / unquoted / leading blank 等）を保ったまま round-trip する（後述 Section 6 AC を参照）

- オプション要件:
  - 折りたたみデフォルト（PRD AC）

## 4. 非機能要件

- パフォーマンス: 通常サイズの markdown（~1MB 程度）で `onChange(text)` 経路がメインスレッドをブロックしないこと（10MB クラスでの最適化は KMD-67 別 issue で扱う）
- アクセシビリティ: 既存 SwiftUI 標準コントロール水準（細かな VoiceOver / Dynamic Type 改善は別 issue で carve-out 済み）
- macOS との整合性: NSTextView との同期ループを発生させない

## 5. UI/UX

```
+---------------------------------------------------+
| [v] Frontmatter — title preview         3 tags    |
+---------------------------------------------------+
| Title       [____________________]                |
| Category    [____________________]                |
| Tags        [swift, ios          ]                |
| Aliases     [____________________]                |
| Date        [2026-05-09T12:00:00Z]                |
| Description [____________________]                |
+---------------------------------------------------+
| (Other fields preserved (not editable here): N)   |
+===================================================+
| (NSTextView 本文 / frontmatter raw 行は現状許容)   |
+---------------------------------------------------+
```

## 6. 受け入れ条件 (Acceptance Criteria)

### 既存 AC（PR #101 で対応済み）
- [x] frontmatter ありのファイルを開くと、エディタ上部に構造化フォーム（title / category / tags / etc.）が表示される
- [x] フォーム編集が YAML に正しく反映される
- [x] frontmatter なしのファイルでは「Add frontmatter」ボタンを表示
- [x] YAML 構文エラー時は警告表示
- [x] 折りたたみ可能（デフォルト折りたたみ）

### 新規 AC（rework で追加 — 書式保持 / 文字列一致運用）
- [ ] **AC-R1: 完全 round-trip 不変性**: ユーザーがフォームから何も編集しない場合、`parse → render` で frontmatter テキストが文字列レベルで一致する（split → frontmatterText が一致する）。これは以下の表現バリエーションすべてで成立すること:
  - inline list (`tags: [swift, ios]`) → そのまま inline list を維持
  - block list (`tags:\n  - swift\n  - ios`) → そのまま block list を維持
  - quoted string (`title: "Hello"`) → quoted を維持（不要な quote を勝手に剥がさない）
  - unquoted string (`title: Hello`) → unquoted を維持（不要な quote を勝手に付けない）
  - 単独 scalar tag (`tags: swift`) → そのまま単独 scalar を維持
  - leading blank / 行末空白 等の本質に関わらない文字も保持（タブ・末尾空白・空行を意味的等価で残す）
- [ ] **AC-R2: 部分編集時の最小差分**: ユーザーが特定フィールドのみフォームから編集した場合、変更したフィールドのみが render で書き換わり、他のフィールドの YAML 表現は AC-R1 と同じく保たれる
- [ ] **AC-R3: 編集による表現変化の許容**: ユーザーがフォームから tags を編集した結果、表現フォーマットが切り替わる場合の挙動を仕様として定義する
  - 元が inline list → 編集後も inline list で書き戻す（block list に強制変換しない）
  - 元が block list → 編集後も block list を維持
  - 元が単独 scalar (`tags: swift`) で、編集により要素数が 2 以上になった場合のみ inline list (`[a, b]`) にフォールバック
  - 元 frontmatter になかった (extraLines にもなかった) フィールドを新規追加した場合は block list (現行の render) を採用
- [ ] **AC-R4: 既存ノート（block list 形式）と KMD-66 (`TagsViewModel.extractTags`) の互換性は維持**

### 非ゴール（書式保持の対象外）
- 行末コメント (`tags: [a, b] # comment`) の保存: 現状サポートしない（extraLines に含まれない場合は失われ得る）。実装上のベストエフォートで保持する。
- マルチライン scalar (`|` / `>`) の round-trip: 現状非対応（extraLines 経由で保持を試みる程度）
- ネスト dict は parseError 警告 + extraLines 保存の現行挙動を維持

## 7. テスト戦略

- 単体テスト（既存 16 ケース + 以下を追加）:
  - `parse_renderRoundTrip_inlineList`: `tags: [swift, ios]` → render で文字列完全一致
  - `parse_renderRoundTrip_blockList`: `tags:\n  - swift\n  - ios` → render で文字列完全一致
  - `parse_renderRoundTrip_quotedTitle`: `title: "Hello"` → render で `title: "Hello"` を維持
  - `parse_renderRoundTrip_unquotedTitle`: `title: Hello` → render で `title: Hello` を維持（quote が増えない）
  - `parse_renderRoundTrip_scalarTag`: `tags: swift` → render で `tags: swift` を維持
  - `parse_renderRoundTrip_aliasesInline`: `aliases: [kb, notes]` → inline 維持
  - `parse_renderRoundTrip_full`: 既存 `render_roundTrip` を「文字列一致」に格上げ（split → frontmatterText の完全一致）
  - `edit_inlineListPreservesFormat`: inline list の最初の要素を変更しても block list に変換されない
  - `edit_scalarTagToList_promotesToInline`: 単独 scalar で要素数 2+ にした場合 inline list で書き戻し
- スナップショット: 既存方針に従う
- 手動確認: 既存ノート (block / inline 混在) を開いて、フォームを触らずに保存して diff が発生しないこと

## 8. 想定リスク・依存

### 影響範囲マップ

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/Models/Frontmatter.swift` | 変更 | 書式メモを保持するため `Frontmatter` 構造体に format hint を追加 (例: `tagsFormat` enum) し、`parse` で記録、`render` で参照 |
| `Sources/ViewModels/FrontmatterViewModel.swift` | 影響なしに保つ | apply の流れは現行維持 |
| `Sources/Views/Editor/FrontmatterEditor.swift` | 影響なし | UI に変更なし |
| `Tests/kobaamdTests/FrontmatterTests.swift` | 追加 | 書式保持テスト追加 |

**共有コンテナへの注意**:
- `Frontmatter` 構造体は KMD-66 (`TagsViewModel.extractTags`) と KMD-67 自身が利用する。`tags` の値型 `[String]` は変えない（KMD-66 互換性維持のため）
- 変更してはいけない箇所:
  - `tags: [String]` / `aliases: [String]` の **公開フィールド型**（互換性のため不変）
  - `parseListBlock` / `parseInlineListOrScalar` の **解釈ルール**（既存ノートの読み取り互換性）
  - `extraLines` の保存ポリシー（情報損失ゼロ）
  - `EditorView.swift` の VStack 構造（concern 2 の二重表示は人間判断で「現状で許容」となったため変更しない）

### その他リスク
- 既存コードへの影響: `Frontmatter` 構造体に format hint フィールドを追加する場合、`Equatable` の実装を意識（hint の差は ==で見るかどうか）
- 互換性: KMD-66 `TagsViewModel.extractTags` は inline list 形式 (`tags: [a, b]`) と block list 形式の両方を読める必要があるため、format 切替後も extractTags が動作することを test で担保
- 外部依存: なし（自前 YAML パーサ）

## 9. 計測・成果指標

「文字列一致」運用が崩れた件数（diff が発生したのに編集していないケース）を 0 件に。

## 10. 参考資料

- レビュー結果: KMD-67 Linear comment (kobaamd_review_pr / 2026-05-09)
- 人間フィードバック: KMD-67 Linear comment (es57ster / 2026-05-09T02:10:13Z)
  - 「1. 文字列一致として運用で、本prで対応とする。」 → AC-R1〜R3 として明文化
  - 「2. 現状で許容」 → frontmatter の二重表示は本 PR スコープ外

## 11. Gemini 調査ログ

<details>
<summary>Gemini 調査ログ — 本 rework では追加の Gemini 調査は行っていない</summary>

本 rework は人間からの明確な指示（文字列一致運用）に基づく実装のため、追加の Gemini 調査は行わず、初回 PR レビュー時の Gemini 検証ログ (Linear comment, 2026-05-09T01:00:26Z) を参照する。

</details>
