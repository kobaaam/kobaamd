---
linear: KMD-XX
status: backlog
created_at: YYYY-MM-DD
author: <human or agent name>
---

# <機能名>

## 1. 背景・目的
（なぜこの機能を作るのか。kobaamd ビジョン・既存ロードマップ・ユーザー利便性とのつながり）

## 2. ターゲットユーザーとユースケース
（誰がどんな場面で使うか）

## 3. 機能要件
- 必須要件:
- オプション要件:

## 4. 非機能要件
- パフォーマンス:
- アクセシビリティ:
- macOS との整合性:

## 5. UI/UX
（ASCII ワイヤーやレイアウト記述。SwiftUI Preview のスクショへのリンクも可）

```
+----+--------+--------+
| Si | Editor | Outline|
| de |        |        |
+----+--------+--------+
```

## 6. 受け入れ条件 (Acceptance Criteria)
- [ ] 条件1
- [ ] 条件2

## 7. テスト戦略
- 単体テスト:
- スナップショット:
- 手動確認:

## 8. 想定リスク・依存

### 影響範囲マップ
<!-- 実装前に必ず埋める。Codex プロンプトの「触れないもの一覧」の根拠になる -->

| ファイル / モジュール | 変更種別 | 備考 |
|---|---|---|
| `Sources/...` | 追加 / 変更 / 削除 | |

**共有コンテナへの注意**（複数機能が同居するファイルを変更する場合は必ず記載）:
- 対象ファイルを使っている他機能:
- 変更してはいけない箇所:

### その他リスク
- 既存コードへの影響:
- 互換性:
- 外部依存:

## 9. 計測・成果指標
（リリース後の評価指標。任意）

## 10. 参考資料
（類似 OSS、関連技術ドキュメント）

## 11. Gemini 調査ログ
<!--
create_prd / review_prd で Gemini を呼び出した際の生プロンプト + 生回答 + 呼び出し時刻 + モデル名を時系列で記録する。
このセクションは折り畳み（details タグ）。review_prd は Step 4 冒頭でここを読み、
同じ機能領域の Gemini 回答が記録済みなら再呼び出しせずに「create_prd 時の回答 + PRD への反映度」を評価する。
重複 Gemini calls を抑制し、PRD レビューサイクルの cost を下げるための共有ログ。

エントリのテンプレ:
- timestamp: ISO8601 (UTC or +0900 でよい。実際の呼び出し時刻)
- agent: kobaamd_create_prd / kobaamd_review_prd
- model: gemini-3.1-pro-preview など実際に叩いたモデル
- topic: A. UI/UX デザインリサーチ / B. 技術実装リサーチ / C. 競合比較 / その他
- prompt: 実際に Gemini に渡した text（要約せず生文）
- response: Gemini の生回答（要約せず生文）
- reflected_in: PRD のどのセクションに反映したか（例: Section 5 ワイヤー / Section 8 リスク）
-->

<details>
<summary>Gemini 調査ログ（create_prd / review_prd 共有 — クリックで展開）</summary>

### Entry 1
- **timestamp**: YYYY-MM-DDTHH:MM:SS+0900
- **agent**: kobaamd_create_prd
- **model**: gemini-3.1-pro-preview
- **topic**: A. UI/UX デザインリサーチ / B. 技術実装リサーチ / C. 競合比較 / その他
- **prompt**:
  ```
  <Gemini に渡した生プロンプト>
  ```
- **response**:
  ```
  <Gemini の生回答>
  ```
- **reflected_in**: Section X（どこに反映したか）

<!-- 追加エントリは Entry 2, Entry 3 ... と連番で append する。既存エントリを書き換えない（履歴として残す） -->

</details>

