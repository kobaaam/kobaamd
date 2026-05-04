#!/usr/bin/env bash
set -euo pipefail

# scripts/wiki/benchmark.sh
#
# Prompt Caching benchmark report generator for the kobaamd LLM Wiki.
# API call はしない。理論値推計モードのみ。
#
# For each query this script emits a theoretical cache-off leg and a
# theoretical cache-on leg, aggregates token / cost / latency estimates,
# and prints a Markdown report. The report structure is kept compatible
# with KMD-48: pricing, latency, token breakdown, cost breakdown,
# breakeven, Cosmos KB linear extrapolation, and query list.

usage() {
  printf '%s\n' \
    'Usage: benchmark.sh [options]' \
    '' \
    'Generate a theoretical Prompt Caching benchmark report for the kobaamd Wiki.' \
    'This script never performs network calls.' \
    '' \
    'Options:' \
    '  --queries <file>   File with one query per line (default: built-in set)' \
    '  --repeat <n>       Repetitions per leg (default: 10)' \
    '  --model <id>       Model id for the pricing table (default: claude-opus-4-5)' \
    '  --max-tokens <n>   Output token cap used by the estimate (default: 256)' \
    '  --out <path>       Write Markdown summary to this file (default: stdout)' \
    '  --json <path>      Also write the per-request JSON log to this file' \
    '  --label <text>     Free-form label included in the report' \
    '  --warm             Treat cache-create as a warm-up shot outside the measured cache-on leg (default)' \
    '  --no-warm          Include the first cache-create inside the measured cache-on leg' \
    '  -h, --help         Show this help and exit.' \
    '' \
    'Examples:' \
    '  scripts/wiki/benchmark.sh' \
    '  scripts/wiki/benchmark.sh --model claude-sonnet-4-5 --repeat 5 --json /tmp/benchmark.json'
}

err() {
  printf 'benchmark.sh: %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 1
  fi
}

is_nonneg_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# ---------- argument parsing ------------------------------------------------

queries_file=""
repeat=10
model="claude-opus-4-5"
max_tokens=256
out_path=""
json_path=""
label=""
warm=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --queries)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      queries_file="$2"; shift 2 ;;
    --repeat)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      repeat="$2"; shift 2 ;;
    --model)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      model="$2"; shift 2 ;;
    --max-tokens)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      max_tokens="$2"; shift 2 ;;
    --out)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      out_path="$2"; shift 2 ;;
    --json)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      json_path="$2"; shift 2 ;;
    --label)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      label="$2"; shift 2 ;;
    --warm)
      warm=1; shift ;;
    --no-warm)
      warm=0; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "unknown argument: $1"; usage >&2; exit 2 ;;
  esac
done

require_cmd jq
require_cmd awk

if ! is_nonneg_int "$repeat" || [ "$repeat" -eq 0 ]; then
  err "--repeat must be a positive integer"
  exit 2
fi

if ! is_nonneg_int "$max_tokens" || [ "$max_tokens" -eq 0 ]; then
  err "--max-tokens must be a positive integer"
  exit 2
fi

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  err "not in a git repository (run from kobaamd repo)"
  exit 1
fi

load_all="$ROOT/scripts/wiki/load_all.sh"
if [ ! -x "$load_all" ]; then
  err "scripts/wiki/load_all.sh not found or not executable"
  exit 1
fi

# ---------- pricing table ---------------------------------------------------
#
# All values are USD per 1,000,000 tokens. Source: Anthropic public pricing
# at the time of writing (2026-05).
#
# Cache write (ephemeral, 5-min TTL): 1.25x input
# Cache read:                         0.10x input

price_for_model() {
  # echo "<input> <output> <cache_write> <cache_read>"
  case "$1" in
    claude-opus-4-5|claude-opus-4-7*|claude-opus-4-7-1m)
      echo "15.00 75.00 18.75 1.50" ;;
    claude-sonnet-4-5*|claude-sonnet-4*)
      echo "3.00 15.00 3.75 0.30" ;;
    claude-haiku-4*|claude-haiku-3-5*)
      echo "0.80 4.00 1.00 0.08" ;;
    *)
      echo "15.00 75.00 18.75 1.50" ;;
  esac
}

read -r price_in price_out price_cw price_cr <<<"$(price_for_model "$model")"

# ---------- queries ---------------------------------------------------------

default_queries=(
  "kobaamd の Prompt Caching 運用ポリシーを 3 行で要約してください。"
  "自律開発パイプラインの定期実行バンドル 3 本を、頻度と中身付きで列挙してください。"
  "kobaamd_review_pr が concern を分類する 3 つのカテゴリ（rework / auto-carveable / human-judgment）の違いを 1 行ずつで説明してください。"
)

queries=()
if [ -n "$queries_file" ]; then
  if [ ! -f "$queries_file" ]; then
    err "queries file not found: $queries_file"
    exit 1
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    queries+=("$line")
  done <"$queries_file"
else
  queries=("${default_queries[@]}")
fi

if [ "${#queries[@]}" -eq 0 ]; then
  err "no queries to run"
  exit 1
fi

# ---------- workspace -------------------------------------------------------

wiki_tmp=$(mktemp)
load_log=$(mktemp)
log_tmp=$(mktemp)

cleanup() {
  rm -f "$wiki_tmp" "$load_log" "$log_tmp"
}
trap cleanup EXIT

if ! "$load_all" >"$wiki_tmp" 2>"$load_log"; then
  err "load_all.sh failed"
  cat "$load_log" >&2
  exit 1
fi

cat "$load_log" >&2

wiki_bytes=$(wc -c <"$wiki_tmp" | awk '{print $1}')
wiki_tokens_est=$(awk -v b="$wiki_bytes" 'BEGIN { printf "%d", b/4 }')

# ---------- theoretical model -----------------------------------------------

estimate_output_tokens() {
  local query="$1"
  local query_bytes out
  query_bytes=$(printf '%s' "$query" | wc -c | awk '{print $1}')
  out=$(awk -v qb="$query_bytes" -v cap="$max_tokens" 'BEGIN {
    est = 96 + int(qb / 6);
    if (est < 96) est = 96;
    if (est > cap) est = cap;
    printf "%d", est;
  }')
  printf '%s\n' "$out"
}

estimate_query_overhead_tokens() {
  local query="$1"
  local query_bytes overhead
  query_bytes=$(printf '%s' "$query" | wc -c | awk '{print $1}')
  overhead=$(awk -v qb="$query_bytes" 'BEGIN {
    est = 42 + int(qb / 4);
    if (est < 42) est = 42;
    printf "%d", est;
  }')
  printf '%s\n' "$overhead"
}

estimate_latency_ms() {
  local mode="$1" phase="$2"
  case "$mode:$phase" in
    off:measured) printf '%s\n' "2400" ;;
    on:create) printf '%s\n' "2200" ;;
    on:read) printf '%s\n' "900" ;;
    *) printf '%s\n' "0" ;;
  esac
}

estimate_once() {
  local mode="$1" query="$2" phase="$3" nonce="$4"
  local uncached_tokens output_tokens input_tokens cache_create_tokens cache_read_tokens latency_ms

  uncached_tokens=$(estimate_query_overhead_tokens "$query")
  output_tokens=$(estimate_output_tokens "$query")
  cache_create_tokens=0
  cache_read_tokens=0

  if [ "$mode" = "off" ]; then
    input_tokens=$((wiki_tokens_est + uncached_tokens))
    latency_ms=$(estimate_latency_ms "off" "measured")
  else
    input_tokens="$uncached_tokens"
    if [ "$phase" = "create" ]; then
      cache_create_tokens="$wiki_tokens_est"
      latency_ms=$(estimate_latency_ms "on" "create")
    else
      cache_read_tokens="$wiki_tokens_est"
      latency_ms=$(estimate_latency_ms "on" "read")
    fi
  fi

  jq -n \
    --arg mode "$mode" \
    --arg query "$query" \
    --arg phase "$phase" \
    --arg nonce "$nonce" \
    --argjson lat "$latency_ms" \
    --argjson sin "$input_tokens" \
    --argjson sout "$output_tokens" \
    --argjson scw "$cache_create_tokens" \
    --argjson scr "$cache_read_tokens" \
    --argjson uncached "$uncached_tokens" \
    '{
      mode: $mode,
      query: $query,
      phase: $phase,
      nonce: $nonce,
      latency_ms: $lat,
      ok: true,
      theoretical: true,
      usage: {
        input_tokens: $sin,
        output_tokens: $sout,
        cache_creation_input_tokens: $scw,
        cache_read_input_tokens: $scr,
        uncached_input_tokens_est: $uncached
      }
    }'
}

# ---------- main loop -------------------------------------------------------

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[]" >"$log_tmp"

run_idx=0
total_queries=${#queries[@]}
total_calls=$((total_queries * repeat * 2))

err "mode=theoretical-estimate model=$model repeat=$repeat queries=$total_queries total_calls=$total_calls wiki_tokens_est=$wiki_tokens_est"

for q in "${queries[@]}"; do
  for i in $(seq 1 "$repeat"); do
    run_idx=$((run_idx + 1))
    nonce="off-${run_idx}-${i}"
    err "[$run_idx/$total_calls] mode=off rep=$i q=\"${q:0:48}...\""
    rec=$(estimate_once "off" "$q" "measured" "$nonce")
    jq --argjson rec "$rec" '. + [$rec]' "$log_tmp" >"${log_tmp}.next"
    mv "${log_tmp}.next" "$log_tmp"
  done

  if [ "$warm" -eq 1 ]; then
    err "[warm-up] mode=on phase=create (not counted)"
    estimate_once "on" "$q" "create" "warm-${run_idx}" >/dev/null
  fi

  for i in $(seq 1 "$repeat"); do
    run_idx=$((run_idx + 1))
    nonce="on-${run_idx}-${i}"
    if [ "$warm" -eq 0 ] && [ "$i" -eq 1 ]; then
      phase="create"
    else
      phase="read"
    fi
    err "[$run_idx/$total_calls] mode=on phase=$phase rep=$i q=\"${q:0:48}...\""
    rec=$(estimate_once "on" "$q" "$phase" "$nonce")
    jq --argjson rec "$rec" '. + [$rec]' "$log_tmp" >"${log_tmp}.next"
    mv "${log_tmp}.next" "$log_tmp"
  done
done

finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---------- aggregation -----------------------------------------------------

agg_json=$(jq -n \
  --slurpfile log "$log_tmp" \
  --argjson pin "$price_in" \
  --argjson pout "$price_out" \
  --argjson pcw "$price_cw" \
  --argjson pcr "$price_cr" \
  '
  def stats(rs):
    (rs | length) as $n
    | if $n == 0 then
        { n: 0 }
      else
        (reduce rs[] as $r (
          { lat:0, in:0, out:0, cw:0, cr:0, ok:0 };
          .lat += ($r.latency_ms // 0)
          | .in += (($r.usage.input_tokens // 0) | tonumber)
          | .out += (($r.usage.output_tokens // 0) | tonumber)
          | .cw += (($r.usage.cache_creation_input_tokens // 0) | tonumber)
          | .cr += (($r.usage.cache_read_input_tokens // 0) | tonumber)
          | .ok += (if $r.ok then 1 else 0 end)
        )) as $s
        | {
            n: $n,
            ok: $s.ok,
            avg_latency_ms: ($s.lat / $n),
            avg_input_tokens: ($s.in / $n),
            avg_output_tokens: ($s.out / $n),
            avg_cache_create_tokens: ($s.cw / $n),
            avg_cache_read_tokens: ($s.cr / $n)
          }
      end;

  def cost(s):
    if (s.n // 0) == 0 then null
    else
      (s.avg_input_tokens * $pin / 1000000.0) as $usd_in
      | (s.avg_output_tokens * $pout / 1000000.0) as $usd_out
      | (s.avg_cache_create_tokens * $pcw / 1000000.0) as $usd_cw
      | (s.avg_cache_read_tokens * $pcr / 1000000.0) as $usd_cr
      | s + {
          usd_input: $usd_in,
          usd_output: $usd_out,
          usd_cache_create: $usd_cw,
          usd_cache_read: $usd_cr,
          usd_total: ($usd_in + $usd_out + $usd_cw + $usd_cr)
        }
    end;

  ($log[0]) as $records
  | ([$records[] | select(.mode == "off" and .ok == true)]) as $off
  | ([$records[] | select(.mode == "on" and .ok == true)]) as $on
  | {
      off: (cost(stats($off))),
      on: (cost(stats($on))),
      records: $records
    }')

# ---------- markdown report -------------------------------------------------

machine="$(uname -m)"
host="$(uname -n)"
mode_label="theoretical-estimate"

avg_off_lat=$(jq -r '.off.avg_latency_ms // 0' <<<"$agg_json")
avg_on_lat=$(jq -r '.on.avg_latency_ms // 0' <<<"$agg_json")
avg_off_in=$(jq -r '.off.avg_input_tokens // 0' <<<"$agg_json")
avg_on_in=$(jq -r '.on.avg_input_tokens // 0' <<<"$agg_json")
avg_off_out=$(jq -r '.off.avg_output_tokens // 0' <<<"$agg_json")
avg_on_out=$(jq -r '.on.avg_output_tokens // 0' <<<"$agg_json")
avg_off_cw=$(jq -r '.off.avg_cache_create_tokens // 0' <<<"$agg_json")
avg_on_cw=$(jq -r '.on.avg_cache_create_tokens // 0' <<<"$agg_json")
avg_off_cr=$(jq -r '.off.avg_cache_read_tokens // 0' <<<"$agg_json")
avg_on_cr=$(jq -r '.on.avg_cache_read_tokens // 0' <<<"$agg_json")
usd_off_total=$(jq -r '.off.usd_total // 0' <<<"$agg_json")
usd_on_total=$(jq -r '.on.usd_total // 0' <<<"$agg_json")
usd_off_in=$(jq -r '.off.usd_input // 0' <<<"$agg_json")
usd_on_in=$(jq -r '.on.usd_input // 0' <<<"$agg_json")
usd_off_out=$(jq -r '.off.usd_output // 0' <<<"$agg_json")
usd_on_out=$(jq -r '.on.usd_output // 0' <<<"$agg_json")
usd_off_cw=$(jq -r '.off.usd_cache_create // 0' <<<"$agg_json")
usd_on_cw=$(jq -r '.on.usd_cache_create // 0' <<<"$agg_json")
usd_off_cr=$(jq -r '.off.usd_cache_read // 0' <<<"$agg_json")
usd_on_cr=$(jq -r '.on.usd_cache_read // 0' <<<"$agg_json")
n_off=$(jq -r '.off.n // 0' <<<"$agg_json")
n_on=$(jq -r '.on.n // 0' <<<"$agg_json")
ok_off=$(jq -r '.off.ok // 0' <<<"$agg_json")
ok_on=$(jq -r '.on.ok // 0' <<<"$agg_json")

cosmos_scale=$(awk -v t="$wiki_tokens_est" 'BEGIN { if (t <= 0) print 0; else printf "%.4f", 10000000.0 / t }')
cosmos_off_usd=$(awk -v u="$usd_off_total" -v s="$cosmos_scale" 'BEGIN { printf "%.4f", u * s }')
cosmos_on_usd=$(awk -v u="$usd_on_total" -v s="$cosmos_scale" 'BEGIN { printf "%.4f", u * s }')

saved_usd=$(awk -v a="$usd_off_total" -v b="$usd_on_total" 'BEGIN { printf "%.6f", a - b }')
saved_pct=$(awk -v a="$usd_off_total" -v b="$usd_on_total" 'BEGIN { if (a == 0) print 0; else printf "%.1f", (a - b) / a * 100 }')
saved_lat_pct=$(awk -v a="$avg_off_lat" -v b="$avg_on_lat" 'BEGIN { if (a == 0) print 0; else printf "%.1f", (a - b) / a * 100 }')

full_cache_write_cost=$(awk -v tokens="$wiki_tokens_est" -v pcw="$price_cw" 'BEGIN { printf "%.6f", tokens * pcw / 1000000.0 }')
steady_read_cost=$(awk -v uncached="$avg_on_in" -v out="$avg_on_out" -v cr="$wiki_tokens_est" -v pin="$price_in" -v pout="$price_out" -v pcr="$price_cr" 'BEGIN {
  total = (uncached * pin + out * pout + cr * pcr) / 1000000.0;
  printf "%.6f", total;
}')
steady_savings=$(awk -v off="$usd_off_total" -v on="$steady_read_cost" 'BEGIN { printf "%.6f", off - on }')
breakeven=$(awk -v write="$full_cache_write_cost" -v save="$steady_savings" 'BEGIN {
  if (save <= 0) print "n/a";
  else printf "%.2f", write / save;
}')

write_report() {
  local out="$1"
  if [ -n "$out" ]; then
    exec >"$out"
  fi

  cat <<HEADER
# Prompt Caching ベンチマーク結果 (KMD-48)

> **注意**: 本レポートは公開 pricing と公開ドキュメント値からの **理論値推計** であり、実 API 計測ではない。実測値が必要な場合は Claude Code / Claude Cowork のセッション usage 観測で補う必要がある（KB1 シリーズ別 issue で扱う）。

- 計測日時: ${started_at} → ${finished_at} (UTC)
- 実行モード: ${mode_label}
- モデル: \`${model}\`
- 文書サイズ: ~${wiki_tokens_est} tokens（\`scripts/wiki/load_all.sh\` 出力 / docs/wiki/articles/）
- 実行マシン: \`${host}\` (${machine})
- ラベル: ${label:-"(none)"}
- クエリ件数: ${total_queries} / クエリ毎 repeat: ${repeat}
- 成功率: cache-off ${ok_off}/${n_off}, cache-on ${ok_on}/${n_on}
- ウォームアップ: $( [ "$warm" -eq 1 ] && echo "1 shot (cache-on, 計測対象外)" || echo "なし" )

## 価格表 (USD / 1M tokens)

| input | output | cache write (5min ephemeral) | cache read |
|---|---|---|---|
| \$${price_in} | \$${price_out} | \$${price_cw} | \$${price_cr} |

> 価格は \`scripts/wiki/benchmark.sh\` の \`price_for_model\` テーブル（2026-05 時点）。
> 改定時はスクリプト側を更新する。

## 1 リクエストあたりの平均

### レイテンシ (ms)

| mode | n | ok | avg latency |
|---|---|---|---|
| cache-off | ${n_off} | ${ok_off} | $(printf '%.1f' "$avg_off_lat") ms |
| cache-on  | ${n_on}  | ${ok_on}  | $(printf '%.1f' "$avg_on_lat") ms |
| **改善幅** | – | – | **${saved_lat_pct}%** |

### トークン分解（平均、1 リクエストあたり）

| mode | input | output | cache_create | cache_read |
|---|---|---|---|---|
| cache-off | $(printf '%.0f' "$avg_off_in") | $(printf '%.0f' "$avg_off_out") | $(printf '%.0f' "$avg_off_cw") | $(printf '%.0f' "$avg_off_cr") |
| cache-on  | $(printf '%.0f' "$avg_on_in")  | $(printf '%.0f' "$avg_on_out")  | $(printf '%.0f' "$avg_on_cw")  | $(printf '%.0f' "$avg_on_cr")  |

### コスト分解（USD、1 リクエストあたり平均）

| mode | input | output | cache_create | cache_read | **total** |
|---|---|---|---|---|---|
| cache-off | \$$(printf '%.6f' "$usd_off_in") | \$$(printf '%.6f' "$usd_off_out") | \$$(printf '%.6f' "$usd_off_cw") | \$$(printf '%.6f' "$usd_off_cr") | **\$$(printf '%.6f' "$usd_off_total")** |
| cache-on  | \$$(printf '%.6f' "$usd_on_in")  | \$$(printf '%.6f' "$usd_on_out")  | \$$(printf '%.6f' "$usd_on_cw")  | \$$(printf '%.6f' "$usd_on_cr")  | **\$$(printf '%.6f' "$usd_on_total")** |
| **節約幅** | – | – | – | – | **\$$(printf '%.6f' "$saved_usd") (${saved_pct}%)** |

## 損益分岐点

- 初回 cache write コスト（wiki 全件）: \$${full_cache_write_cost}
- 定常 cache read 1 回あたりの推計コスト: \$${steady_read_cost}
- cache-off 比の 1 回あたり節約額: \$${steady_savings}
- **初回書込みを償却するのに必要な cache-read 回数**: ${breakeven}

> \`--warm\` は cache write を計測対象外に追い出し、定常 read を見やすくするための前提。
> \`--no-warm\` は最初の cache-on リクエストへ cache write を載せ、初回呼び出し込みの平均を出す前提。
> どちらのモードでも breakeven 自体は「初回 write を何回の read で回収するか」の理論値として同じ式で計算している。

## Cosmos KB（10M tokens）への線形外挿

スケール = 10,000,000 / ${wiki_tokens_est} ≈ ×${cosmos_scale}

| シナリオ | 1 リクエスト USD（外挿） |
|---|---|
| cache-off | \$$(printf '%.4f' "$cosmos_off_usd") |
| cache-on  | \$$(printf '%.4f' "$cosmos_on_usd") |

> 外挿はトークン数を線形にスケールした単純試算。実際には:
> - 文書部分が 200k token を超えると prompt cache 上限に当たり、Phase 3（embedding 検索層）への移行が必要
> - 出力トークン数はクエリ依存で線形外挿しないため、出力コストは概算
> - 実運用では cache hit ratio < 1 になる（TTL 切れ・コンテキスト変更・セッション分裂）

## 計測条件

- \`scripts/wiki/load_all.sh\` の出力サイズから wiki token 数を \`bytes / 4\` で推計
- cache-off は「wiki 全文を毎回 input 課金」とみなす
- cache-on は「uncached portion + cache read」、\`--no-warm\` の最初の 1 回だけ cache write を加算する
- レイテンシは公開ドキュメント上の傾向に合わせた理論値（cache-off 2400ms / cache-read 900ms / cache-create 2200ms）
- 出力 token はクエリ長と \`--max-tokens\` 上限から決める保守的な推計値

## クエリ一覧

HEADER

  local i=1
  for q in "${queries[@]}"; do
    printf '%d. %s\n' "$i" "$q"
    i=$((i + 1))
  done
}

if [ -n "$out_path" ]; then
  write_report "$out_path"
  err "report -> $out_path"
else
  write_report ""
fi

if [ -n "$json_path" ]; then
  jq -n \
    --arg started "$started_at" \
    --arg finished "$finished_at" \
    --arg model "$model" \
    --arg mode "$mode_label" \
    --argjson repeat "$repeat" \
    --argjson warm "$warm" \
    --argjson max_tokens "$max_tokens" \
    --argjson wiki_tokens_est "$wiki_tokens_est" \
    --argjson agg "$agg_json" \
    '{
      started_at: $started,
      finished_at: $finished,
      mode: $mode,
      model: $model,
      repeat: $repeat,
      warm: ($warm == 1),
      max_tokens: $max_tokens,
      wiki_tokens_est: $wiki_tokens_est,
      aggregated: $agg
    }' >"$json_path"
  err "json log -> $json_path"
fi
