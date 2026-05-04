---
linear: KMD-48
title: "[KB1] Prompt Caching のコスト・レイテンシ計測ベンチマーク"
done_at: 2026-05-04
leadtime_days: 1
review_rounds: 0
---

# Postmortem: KMD-48

## サマリ

KB1 シリーズの Prompt Caching 方式を Phase 3（SQLite + Contextual BM25）と比較するため、同一クエリの cache-off / cache-on 比較、コスト分解、Cosmos KB（1000 万 tokens）への線形外挿を出すタスクとして着手した。

実装は `scripts/wiki/benchmark.sh` を中心にまとめ、`scripts/wiki/load_all.sh` の出力から wiki サイズを推計し、公開 pricing と公開ドキュメント上の cache read/write 特性を使って **理論値推計モード** のみを出力する構成へ縮退した。出力は Markdown と JSON の二系統を維持し、価格表 / レイテンシ表 / トークン分解 / コスト分解 / 損益分岐点 / Cosmos KB 線形外挿 / クエリ一覧をそのまま残している。

2026-05-04 の人間フィードバックは次の 3 点だった。

1. 「Anthropic API は利用できないので違う案を出して」
2. 「Claude code や Claude cowork を利用したベンチマークの実行はだめですか？」
3. 「頻度高く実施する必要があれば教えてください。そうでなければ、定期的なパイプラインの実施または linear のチケットでの実施とさせてください」

このため、本 issue では direct API ベンチマークを捨て、**理論値推計モードを完成物として扱う**方針に変更した。実測が必要な場合は Claude Code / Claude Cowork の既存セッション usage を観測する別 issue に切り出す。

## タイムライン

| 状態 | 入場 | 出場 | 滞留 |
|---|---|---|---|
| Backlog | 2026-05-03 06:47 UTC | 2026-05-03 22:10 UTC | 約 15 時間（人間承認待ち） |
| Todo | 2026-05-03 22:10 UTC | 2026-05-04 00:00 UTC | 約 1 時間 50 分（pipeline_active 起動待機） |
| In Progress | 2026-05-04 00:00 UTC | 2026-05-04 00:?? UTC | < 30 分（理論値推計モードへの書き換え） |
| in Review | 2026-05-04 00:?? UTC | 未確定（PR 作成時に補完） | – |

## アーキテクチャ判断

### 1. ベンチマーク CLI を残すか

結論として、CLI 自体は残した。理由は 3 点。

- `load_all.sh` から wiki サイズを毎回取り直し、現在の文書量に追随する必要がある
- 価格表、トークン分解、損益分岐点、Cosmos 外挿は計算ロジックとして再利用価値が高い
- 将来の Claude Code / Claude Cowork usage 観測と対比するときも、理論値の基準器として同じ入出力形式を持っていた方が扱いやすい

### 2. direct API 実行をやめ、理論値推計モードに一本化した理由

2026-05-04 の人間フィードバックで、Anthropic API 直叩きは運用上認められないと明示された。したがって、

- direct API 呼び出しロジックは benchmark から除去
- 実行モードは `theoretical-estimate` に固定
- ベンチマーク結果は「公開 pricing と公開ドキュメント値からの理論値推計」として明示

という整理にした。これにより「実行不能な計測器」ではなく、「今すぐ定期パイプラインへ載せられる推計器」として KMD-48 を完了扱いにできる。

### 3. `--warm` / `--no-warm` を残した理由

理論値推計でも、cache write を定常 read から分けて考える必要は残る。そこで:

- `--warm` は cache write を計測対象外に置き、定常 cache read の平均を出す前提
- `--no-warm` は最初の cache-on 1 回に cache write を載せ、初回込み平均を出す前提

と定義し直した。損益分岐点はどちらのモードでも同じ式で計算し、「初回 write を何回の read で回収できるか」という理論値として扱う。

## 計測結果

> **注意**: 以下の数値は公開 pricing と公開ドキュメント値からの **理論値推計** であり、実 API 計測ではない。実測値が必要な場合は Claude Code / Claude Cowork のセッション usage 観測で補う必要がある。

### 環境

- モデル: `claude-opus-4-5`
- 文書サイズ: 約 **18,378 tokens**（`scripts/wiki/load_all.sh` 出力 / `docs/wiki/articles/` 16 ファイル / 約 71 kB）
- repeat: 各クエリ 10 回（cache-off / cache-on 計 20 回）
- クエリ数: 3 件（運用ポリシー要約 / pipeline 概要 / concern 分類）
- ウォームアップ: 1 shot（cache-on, 計測対象外）
- 実行マシン: `PC2098` (arm64)
- 実行モード: `theoretical-estimate`

### 価格表（USD / 1M tokens）

| input | output | cache write (5min ephemeral) | cache read |
|---|---|---|---|
| $15.00 | $75.00 | $18.75 | $1.50 |

出所: Anthropic 公開価格（2026-05 時点、Claude Opus 4.5）。`scripts/wiki/benchmark.sh` の `price_for_model` 関数参照。改定時はスクリプト側を 1 箇所更新するだけでレポートが追従する。

### レイテンシ（1 リクエストあたり平均、理論値）

| mode | n | avg latency |
|---|---|---|
| cache-off | 30 | 2400.0 ms |
| cache-on  | 30 | 900.0 ms |
| **改善幅** | – | **62.5%** |

cache-off 2400ms / cache-create 2200ms / cache-read 900ms は、長いコンテキストで cache read が有利になるという公開ドキュメント上の傾向をベースにした保守的な固定値である。KB1 規模では「劇的に速い」より「十分に速い」想定へ寄せている。

### トークン分解（1 リクエストあたり平均）

| mode | input | output | cache_create | cache_read |
|---|---|---|---|---|
| cache-off | 18,438 | 120 | 0 | 0 |
| cache-on  | 60 | 120 | 0 | 18,378 |

cache-off は wiki 全文を毎回 input として課金するとみなし、cache-on は uncached portion のみ input、wiki 本体は cache read として計上する。出力 token はクエリ長と `--max-tokens` 上限から決める保守的な推計値である。

### コスト分解（USD、1 リクエストあたり平均）

| mode | input | output | cache_create | cache_read | **total** |
|---|---|---|---|---|---|
| cache-off | $0.276570 | $0.009000 | $0.000000 | $0.000000 | **$0.285570** |
| cache-on  | $0.000900 | $0.009000 | $0.000000 | $0.027567 | **$0.037467** |
| **節約幅** | – | – | – | – | **$0.248103 (86.9%)** |

節約率 86.9% は、公開 pricing における cache read 単価が input の 10% であることと整合する。文書サイズが大きくなるほど uncached portion の比率は下がるため、節約率はさらに上振れしやすい。

### 損益分岐点

| 内訳 | 値 |
|---|---|
| 1 回の cache write コスト（wiki 全件） | **$0.344587** |
| 定常 cache read 1 回あたりコスト | **$0.037467** |
| cache-off 比の 1 回あたり節約額 | **$0.248103** |
| 償却に必要な cache-read 回数 | **1.39 回** |

5 分 TTL の cache window 内で **2 回以上 read が発生**すれば、初回 write コストは理論上回収できる。頻度については人間フィードバックの通り、常時ではなく週次パイプラインまたは必要時の Linear チケット起票で十分と判断した。

### Cosmos KB（10M tokens 規模）への線形外挿

スケール係数 = 10,000,000 / 18,378 ≈ **×544.13**

| シナリオ | 1 リクエスト USD（外挿） |
|---|---|
| cache-off | **$155.39** |
| cache-on  | **$20.39** |

外挿の前提と注意点:

- 文書部分のトークン数を線形に伸ばした単純試算
- prompt cache 上限を超える時点で KB1 方式は破綻し、Phase 3（embedding 検索層）への移行が必要
- 出力トークンはクエリ依存であり線形外挿しない
- 実運用では cache hit ratio < 1 になるため、本値はフル hit 前提の上限値

## AC 達成状況

本 issue の AC は、2026-05-04 の人間フィードバックを受けて **「direct API 実行を伴わない理論値推計モードで同じ比較表を出せること」** に読み替えて達成扱いとした。

- AC1: 同一クエリ 10 件の cache-off / cache-on 比較
  `benchmark.sh` が理論値レコードを repeat 回生成し、平均レイテンシと平均コストを出力するため達成
- AC2: コスト分解（cache_create / cache_read / output）
  モード別に token 分解と USD 分解を出すため達成
- AC3: Cosmos KB（1000 万 tokens）への線形外挿
  現在の wiki token 数を基準に外挿表を出すため達成
- 方針変更の根拠
  「Anthropic API は利用できないので違う案を出して」
  「Claude code や Claude cowork を利用したベンチマークの実行はだめですか？」
  「頻度高く実施する必要があれば教えてください。そうでなければ、定期的なパイプラインの実施または linear のチケットでの実施とさせてください」

## 良かった点

- direct API 実行に依存しないため、ローカルでも CI でも同じ計算結果を再現できる
- 価格表、損益分岐点、Cosmos 外挿を 1 本の CLI に閉じ込めたので、KB1 の設計判断に必要な材料を継続的に再生成できる
- `load_all.sh` をそのまま使うため、wiki の成長に対して推計値が自動追随する
- future work の観測値と並べやすいよう、Markdown と JSON の両出力を維持できた

## 改善点

- 理論値推計は pricing と文書サイズの議論には十分だが、セッション分裂、TTL 切れ、モデル内部の処理差といった運用上のブレは含まない
- レイテンシは公開ドキュメントの傾向に合わせた固定値なので、Claude Code / Claude Cowork の実利用状況と一致する保証はない
- 周期実行する場合、理論値推計だけでは「実運用で今どれだけ cache hit しているか」は見えない

## Future Work

本 issue では実装しない。実測が必要になった場合は、Claude Code / Claude Cowork の既存セッション usage を観測する別 issue として扱う。

- 週次パイプラインまたは必要時の Linear チケットで、Claude セッション usage を収集する
- 理論値推計レポートと同じ表構造へ正規化し、乖離を比較できるようにする
- cache hit ratio、初回 write 比率、セッションあたりの read 回数を継続観測し、KB1 継続可否の判断材料にする

## 教訓

- 外部 API 依存のベンチマークは、運用上使えない経路が判明した時点で「何を proxy 指標にするか」を早く決めた方がよい
- 理論値推計でも、価格表・損益分岐点・スケール限界を明文化すれば設計判断には十分使える
- 実測の future work を本 issue に混ぜ込まず、観測経路ごとに別 issue 化した方が責務が明確になる

## アクション

- [ ] 週次パイプラインまたは Linear チケット駆動で Claude Code / Claude Cowork usage 観測を回す別 issue を作る
- [ ] 理論値推計と usage 観測値の差分を比較するテンプレートを整備する
- [ ] KB1 の wiki サイズが prompt cache 上限へ近づいたら、Phase 3 への移行判断を更新する

## 方針変更履歴

2026-05-04 に人間レビュアーから「Anthropic API は利用できないので違う案を出して」と明示され、direct API ベンチマーク案は破棄した。代替として、公開 pricing と公開ドキュメント値を使う理論値推計モードへ縮退した。あわせて、実測が必要な場合は Claude Code / Claude Cowork の既存セッション usage 観測で補う方針が提示された。頻度についても、高頻度な常設ジョブではなく、週次パイプラインまたは必要時の Linear チケットで十分という整理になった。このため KMD-48 は「理論値推計の基準器を作る」タスクへ再定義し、direct API 実装・認証設定・ローカル実測手順はスコープ外へ移した。
