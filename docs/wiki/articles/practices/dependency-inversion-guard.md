---
title: 依存逆順耐性のためのガードパターン
category: practices
tags: [shell, pipeline, dependency, defensive-coding, weekly]
sources:
  - docs/learnings/2026-05-05-KMD-54.md
created: 2026-05-06
updated: 2026-05-06
---

# 依存逆順耐性のためのガードパターン

## Summary

kobaamd の自律パイプラインでは、依存関係のある複数 PR が並走したときにマージ順序が逆転しうる。本記事では「依存先 script が未配備でも weekly / daily ジョブを落とさないガードパターン」と、それを PRD と実装の両方に書き込む運用を整理する。KMD-54（pipeline_weekly に lint_wiki を組み込み）で実証されたパターン。

## Content

### kobaamd における依存逆順の発生条件
<!-- llm-context: kobaamd の pipeline_active が WIP=1 で動くため、依存元 PR より依存先 PR が後にマージされる現象が発生する条件と典型例。 -->

`kobaamd_assign_work` は Linear の Todo を「入った順」で 1 件ずつ取り出し、parent / blocked-by ラベルを参照しない。そのため、依存先（例: `KMD-52` lint.sh）が Human in Review に滞留している間に、依存元（例: `KMD-54` pipeline_weekly への組み込み）が先に Reviewed → Done まで進むケースが発生する。

KMD-54 の実例では、PR #63（依存元）が PR #62（依存先 lint.sh）より先にマージされ、main 上で lint.sh がまだ存在しない状態で weekly が走る可能性が生じた。

### ガードパターン（依存先 script 不在時 warning + skip + exit=0）
<!-- llm-context: shell の bundle slash で依存先スクリプトの実行可能性をテストし、不在なら warning を出して skip する基本テンプレート。weekly / daily で使う。 -->

依存先 script を呼び出す箇所では、実行可能テストで存在を確認し、不在時は **warning を stderr に出して skip し、exit=0 で抜ける**。weekly 全体を落とさないことを優先する。

```bash
if [[ ! -x ./scripts/wiki/lint.sh ]]; then
  echo "wiki lint: lint.sh not found, skipping (KMD-52 not merged yet)" >&2
else
  ./scripts/wiki/lint.sh --no-llm \
    | ./scripts/wiki/lint_report.sh --threshold 1
fi
```

要点:

- 判定は `[[ ! -x <path> ]]` で実行可能性を見る（`-f` ではなく `-x`。ビルド済み・権限ありを確認）
- skip メッセージには **依存先チケット ID**（例: `KMD-52 not merged yet`）を含めると追跡が容易
- `exit 0` は明示しない（`else` 節を抜ければ slash 全体は成功扱いとなる）
- パイプ後段の script（例: `lint_report.sh`）は前段に依存しない設計にしておく（後述の責務分離と組み合わせる）

### PRD と実装の両方にガードを書く運用
<!-- llm-context: PRD section 8（影響範囲マップ + その他リスク）にガード方針を明記し、レビュー観点として独立評価できるようにする運用ルール。 -->

依存逆順ガードは、PRD と実装の両方で予防的に書く:

1. **PRD section 8「その他リスク」**: 「依存元 PR が先にマージされる可能性」を明文化。ガードコードのスニペット例を含めると implement の指針になる
2. **実装**: 上記スニペットをそのまま slash / script に埋め込む
3. **`kobaamd_review_pr`**: PRD section 8 と実装を突き合わせ、「ガード有り」を独立観点として pass 判定できる

KMD-54 ではこの三段構えにより、レビューがリワーク 0 回でクリーン APPROVE 直行できた。レビュー側が「依存逆順耐性」を pass したことが、PR #62 より先のマージを安全に許容する根拠になった。

### 責務分離との組み合わせ
<!-- llm-context: ガードパターンを書きやすくするには、依存先 script と本 PR の script を責務分離して入出力を疎結合にしておくことが前提となる。 -->

ガードパターンは、依存先 script と本 PR の script を **責務分離して疎結合にしておく** ことが前提となる。KMD-54 では `lint.sh`（NDJSON 出力）と `lint_report.sh`（NDJSON → markdown + Linear comment.add）を分離した:

- `lint.sh` は依存先（KMD-52 範囲）。本 PR では一切触らない（PRD「変更してはいけない箇所」に明記）
- `lint_report.sh` は `lint.sh` に依存せず、stdin の NDJSON だけで完結する単体スクリプト
- weekly slash は両者をパイプで繋ぐだけ

この分離により、`lint.sh` 不在時に `lint_report.sh` 単体テスト（fixture-driven）が成立し、後続の自動テスト整備（KMD-141 として auto carve-out）も書きやすくなる。逆に lint と report が一体だと、依存先の差分でテストが壊れやすい。

### このパターンが転用できる場面
<!-- llm-context: kobaamd の他の bundle slash（pipeline_active / pipeline_daily）や、外部 CLI / ツールに依存する script で同じパターンが応用可能な事例。 -->

KMD-54 の lint.sh 不在ガードは、以下の場面に転用可能:

- `pipeline_active` が新規 subagent / slash に依存する場合（subagent ファイル不在時の skip）
- `pipeline_daily` が `gh` / `jq` 等の外部 CLI に依存する場合（コマンド不在時の skip + 警告）
- 共通ヘルパー（`scripts/wiki/load_all.sh` 等）が未配備の環境で実行されるケース
- D2 / Mermaid のように外部バイナリへ依存するレンダラー（KMD-30 / KMD-31 で扱う `Process()` 排除と並走する論点）

いずれも「**依存先が無くてもジョブ全体は成功扱いで抜け、可視警告を残す**」が共通方針となる。

## Related

- [[postmortem-patterns]] — クリーン APPROVE 直行の 4 条件と auto carve-out 規約
- [[prd-quality-cycle]] — PRD section 8（影響範囲マップ + その他リスク）の品質バー
- [[autonomous-pipeline-philosophy]] — pipeline_active / weekly の責務分担と人間承認ゲート
- [[security-hardening]] — shell quoting / set -euo pipefail / trap cleanup の規約
- [[build-and-test-pipeline]] — `prepare-build.sh` のような依存スクリプトの具体例と、不在時の失敗パターン

## Sources

- docs/learnings/2026-05-05-KMD-54.md
