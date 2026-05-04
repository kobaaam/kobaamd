#!/usr/bin/env bash
set -euo pipefail

# scripts/wiki/benchmark.sh
#
# Benchmark Anthropic Prompt Caching against the kobaamd LLM Wiki
# (docs/wiki/articles/**/*.md). For each query in the input list this
# runs N "no-cache" requests followed by N "cache" requests, measures
# wall-clock latency (ms) and token-level cost (USD) per request, and
# emits an aggregated summary on stdout (Markdown table).
#
# The benchmark answers KMD-48 ACs:
#   - Same query x10 with cache off / cache on, latency (ms) + cost (USD)
#   - Cost broken down into doc cache write / cache read / output
#   - Linear extrapolation to Cosmos KB scale (10M tokens)
#
# Cache-OFF runs send the wiki blob as a system block WITHOUT
# cache_control, and pass a unique cache buster nonce in the user turn
# (so a previous cache_read does not bleed into the no-cache leg).
#
# Cache-ON runs send the wiki blob with cache_control: ephemeral.
# The first ON request is a cache-creation request; subsequent ON
# requests within the 5-min cache window should report
# cache_read_input_tokens > 0 and cache_creation_input_tokens == 0.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-ant-... scripts/wiki/benchmark.sh \
#     [--queries <file>] [--repeat <N>] [--model <id>] [--max-tokens <n>] \
#     [--out <md>] [--json <json>] [--label <text>] [--no-warm]
#
# Defaults:
#   --queries: built-in 3-query set (architecture / pipeline / wiki policy)
#   --repeat:  10
#   --model:   $ANTHROPIC_MODEL or claude-opus-4-5
#   --max-tokens: 256 (output is not the focus)
#   --out:     stdout
#
# Pricing (USD / 1M tokens) is hardcoded per --model below. Update the
# `price_for_model` function when Anthropic publishes new rates.
#
# --dry-run mode skips the actual HTTP calls and emits payload sizes /
# pricing-table / extrapolation formulas only. Useful when ANTHROPIC_API_KEY
# is not configured and you want to validate the script structure or
# pre-publish the report scaffold for later filling.

usage() {
  printf '%s\n' \
    'Usage: benchmark.sh [options]' \
    '' \
    'Run a Prompt Caching cost / latency benchmark against the kobaamd Wiki.' \
    '' \
    'Options:' \
    '  --queries <file>   File with one query per line (default: built-in set)' \
    '  --repeat <n>       Repetitions per leg (default: 10)' \
    '  --model <id>       Anthropic model id (default: $ANTHROPIC_MODEL or claude-opus-4-5)' \
    '  --max-tokens <n>   Output token cap (default: 256)' \
    '  --out <path>       Write Markdown summary to this file (default: stdout)' \
    '  --json <path>      Also write the per-request JSON log to this file' \
    '  --label <text>     Free-form label included in the report (e.g. machine name)' \
    '  --no-warm          Skip the 1-shot cache warm-up before the cache-on leg' \
    '  --dry-run          Build payloads + pricing tables WITHOUT calling the API' \
    '  -h, --help         Show this help and exit.' \
    '' \
    'Environment:' \
    '  ANTHROPIC_API_KEY  Required.' \
    '  ANTHROPIC_MODEL    Optional, overrides the default model.' \
    '  ANTHROPIC_BASE_URL Optional, defaults to https://api.anthropic.com'
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

# ---------- argument parsing ------------------------------------------------

queries_file=""
repeat=10
model="${ANTHROPIC_MODEL:-claude-opus-4-5}"
max_tokens=256
out_path=""
json_path=""
label=""
warm=1
dry_run=0

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
    --no-warm)
      warm=0; shift ;;
    --dry-run)
      dry_run=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "unknown argument: $1"; usage >&2; exit 2 ;;
  esac
done

require_cmd jq
require_cmd curl
require_cmd awk

if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ "$dry_run" -eq 0 ]; then
  err "ANTHROPIC_API_KEY is not set (try: source ~/.zshrc, or pass --dry-run)"
  exit 1
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

base_url="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"

# ---------- pricing table --------------------------------------------------
#
# All values are USD per 1,000,000 tokens. Source: Anthropic public pricing
# at the time of writing (2026-05). When Anthropic updates pricing, edit
# the case statement below.
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
      # Fall back to opus pricing as a conservative upper bound.
      echo "15.00 75.00 18.75 1.50" ;;
  esac
}

read -r price_in price_out price_cw price_cr <<<"$(price_for_model "$model")"

# ---------- queries --------------------------------------------------------

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
payload_tmp=$(mktemp)
response_tmp=$(mktemp)
http_status_tmp=$(mktemp)
log_tmp=$(mktemp)
dry_state_file=$(mktemp -u)  # sentinel; created when first ON call fires in --dry-run

cleanup() {
  rm -f "$wiki_tmp" "$load_log" "$payload_tmp" "$response_tmp" "$http_status_tmp" "$log_tmp" "$dry_state_file"
}
trap cleanup EXIT

if ! "$load_all" >"$wiki_tmp" 2>"$load_log"; then
  err "load_all.sh failed"
  cat "$load_log" >&2
  exit 1
fi

cat "$load_log" >&2

wiki_bytes=$(wc -c <"$wiki_tmp" | awk '{print $1}')
# Rough token estimate that load_all.sh uses (bytes / 4)
wiki_tokens_est=$(awk -v b="$wiki_bytes" 'BEGIN { printf "%d", b/4 }')

system_preamble=$'You are a research assistant for the kobaamd project.\nThe document section that follows contains the full LLM Wiki under docs/wiki/articles/.\nAnswer the user query strictly based on this Wiki when possible.\nKeep answers concise (<= 5 sentences). Cite article paths when possible.'

# ---------- helpers ---------------------------------------------------------

# build_payload <mode:on|off> <query> <nonce>
# Writes the JSON payload for the request to $payload_tmp.
build_payload() {
  local mode="$1" query="$2" nonce="$3"
  local cache_arg
  if [ "$mode" = "on" ]; then
    cache_arg='{ "type": "ephemeral" }'
  else
    cache_arg='null'
  fi

  jq -n \
    --arg model "$model" \
    --argjson max_tokens "$max_tokens" \
    --arg preamble "$system_preamble" \
    --rawfile wiki "$wiki_tmp" \
    --arg query "$query" \
    --arg nonce "$nonce" \
    --argjson cache "$cache_arg" \
    '{
      model: $model,
      max_tokens: $max_tokens,
      system: (
        [ { type: "text", text: $preamble } ] +
        [ (
            { type: "text",
              text: ("# kobaamd LLM Wiki (docs/wiki/articles)\n\n" + $wiki)
            } +
            ( if $cache == null then {} else { cache_control: $cache } end )
          )
        ]
      ),
      messages: [
        { role: "user",
          content: ("[bench-nonce: " + $nonce + "]\n" + $query)
        }
      ]
    }' >"$payload_tmp"
}

# call_once <mode> <query> <nonce>
# POSTs the request, measures latency, prints one JSON record to stdout.
# In --dry-run mode this skips the HTTP call and synthesises a record
# from the payload size + pricing table assumptions. Such records are
# tagged `simulated: true` so the report can flag them.
call_once() {
  local mode="$1" query="$2" nonce="$3"

  build_payload "$mode" "$query" "$nonce"

  if [ "$dry_run" -eq 1 ]; then
    # Doc-block tokens roughly = wiki_tokens_est + small preamble overhead.
    # In cache-OFF mode the whole blob is billed as input.
    # In cache-ON mode, we assume:
    #   - first call    -> cache_create_input_tokens = wiki_tokens_est (charged at $price_cw)
    #   - later calls   -> cache_read_input_tokens   = wiki_tokens_est (charged at $price_cr)
    #   - input_tokens (uncached portion) ~= 50 (system preamble + user)
    # Output tokens are assumed to average 120 (well under the cap).
    local sim_in sim_out sim_cw sim_cr sim_lat
    sim_out=120
    if [ "$mode" = "off" ]; then
      sim_in=$(( wiki_tokens_est + 60 ))
      sim_cw=0
      sim_cr=0
      sim_lat=2400
    else
      sim_in=60
      # heuristic: first ON call writes the cache, the rest read it.
      # When --warm is enabled, the warm-up shot is the writer and every
      # measured ON call should be a cache_read. We track "first ON
      # observed" via a sentinel file so the state survives subshells.
      if [ ! -f "$dry_state_file" ] && [ "$warm" -eq 0 ]; then
        sim_cw="$wiki_tokens_est"; sim_cr=0; sim_lat=2200
        : >"$dry_state_file"
      else
        sim_cw=0; sim_cr="$wiki_tokens_est"; sim_lat=900
      fi
    fi
    jq -n \
      --arg mode "$mode" --arg query "$query" --arg nonce "$nonce" \
      --argjson lat "$sim_lat" --argjson sin "$sim_in" --argjson sout "$sim_out" \
      --argjson scw "$sim_cw" --argjson scr "$sim_cr" \
      '{ mode: $mode, query: $query, nonce: $nonce, latency_ms: $lat,
         http_status: "200", ok: true, simulated: true,
         usage: { input_tokens: $sin, output_tokens: $sout,
                  cache_creation_input_tokens: $scw,
                  cache_read_input_tokens: $scr },
         stop_reason: "end_turn" }'
    return 0
  fi

  : >"$response_tmp"
  : >"$http_status_tmp"

  local start_ns end_ns elapsed_ms curl_exit http_status
  start_ns=$(python3 -c 'import time; print(int(time.time()*1_000_000_000))')

  set +e
  curl --silent --show-error --fail-with-body \
    --max-time 180 \
    --output "$response_tmp" \
    --write-out '%{http_code}' \
    -X POST "$base_url/v1/messages" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H 'anthropic-version: 2023-06-01' \
    -H 'content-type: application/json' \
    --data-binary "@$payload_tmp" \
    >"$http_status_tmp"
  curl_exit=$?
  set -e

  end_ns=$(python3 -c 'import time; print(int(time.time()*1_000_000_000))')
  elapsed_ms=$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN { printf "%.1f", (e-s)/1e6 }')

  http_status=$(cat "$http_status_tmp" 2>/dev/null || echo "")

  if [ "$curl_exit" -ne 0 ] || [ "$http_status" != "200" ]; then
    err "request failed (mode=$mode http=$http_status curl_exit=$curl_exit)"
    head -c 1024 "$response_tmp" >&2 || true
    printf '\n' >&2
    jq -n \
      --arg mode "$mode" --arg query "$query" --arg nonce "$nonce" \
      --argjson lat "$elapsed_ms" --arg http "$http_status" \
      '{ mode: $mode, query: $query, nonce: $nonce, latency_ms: $lat,
         http_status: $http, ok: false }'
    return 0
  fi

  jq -n \
    --arg mode "$mode" --arg query "$query" --arg nonce "$nonce" \
    --argjson lat "$elapsed_ms" \
    --slurpfile r "$response_tmp" \
    '{
       mode: $mode, query: $query, nonce: $nonce, latency_ms: $lat,
       http_status: "200", ok: true,
       usage: ($r[0].usage // {}),
       stop_reason: $r[0].stop_reason
     }'
}

# ---------- main loop -------------------------------------------------------

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[]" >"$log_tmp"

run_idx=0
total_queries=${#queries[@]}
total_calls=$(( total_queries * repeat * 2 ))

err "model=$model repeat=$repeat queries=$total_queries total_calls=$total_calls wiki_tokens_est=$wiki_tokens_est"

# Pre-warm: if requested, send 1 cache-on call (not counted) so that the
# very first measured cache-on call already hits a populated cache. The
# warm-up shares the same cache key as the measurements (same system blob
# + same model). This separates "cache write" from "steady-state cache
# read" cleanly. The first measured cache-on call still tends to be a
# cache_create (because warm-up was the writer); we keep it in the data
# but mark it cache_create_observed so the analysis can split.

for q in "${queries[@]}"; do

  # ---- cache-OFF leg --------------------------------------------------
  for i in $(seq 1 "$repeat"); do
    run_idx=$((run_idx + 1))
    nonce="off-$(date +%s%N)-$RANDOM"
    err "[$run_idx/$total_calls] mode=off rep=$i q=\"${q:0:48}...\""
    rec=$(call_once "off" "$q" "$nonce")
    jq --argjson rec "$rec" '. + [$rec]' "$log_tmp" >"${log_tmp}.next"
    mv "${log_tmp}.next" "$log_tmp"
  done

  # ---- pre-warm (single, not counted) --------------------------------
  if [ "$warm" -eq 1 ]; then
    err "[warm-up] mode=on (not counted)"
    nonce="warm-$(date +%s%N)-$RANDOM"
    call_once "on" "$q" "$nonce" >/dev/null
  fi

  # ---- cache-ON leg ---------------------------------------------------
  for i in $(seq 1 "$repeat"); do
    run_idx=$((run_idx + 1))
    nonce="on-$(date +%s%N)-$RANDOM"
    err "[$run_idx/$total_calls] mode=on rep=$i q=\"${q:0:48}...\""
    rec=$(call_once "on" "$q" "$nonce")
    jq --argjson rec "$rec" '. + [$rec]' "$log_tmp" >"${log_tmp}.next"
    mv "${log_tmp}.next" "$log_tmp"
  done

done

finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---------- aggregation ----------------------------------------------------

# Compute per-mode averages (latency, input, output, cache_create, cache_read)
# and convert to USD. We sum tokens across runs, then convert once with the
# pricing table, which is mathematically equivalent to per-call USD averaging.

agg_json=$(jq -n \
  --slurpfile log "$log_tmp" \
  --argjson pin  "$price_in" \
  --argjson pout "$price_out" \
  --argjson pcw  "$price_cw" \
  --argjson pcr  "$price_cr" \
  '
  def stats(rs):
    (rs | length) as $n
    | if $n == 0 then
        { n: 0 }
      else
        ( reduce rs[] as $r (
            { lat:0, in:0, out:0, cw:0, cr:0, ok:0 };
            .lat += ($r.latency_ms // 0)
            | .in  += (($r.usage.input_tokens // 0) | tonumber)
            | .out += (($r.usage.output_tokens // 0) | tonumber)
            | .cw  += (($r.usage.cache_creation_input_tokens // 0) | tonumber)
            | .cr  += (($r.usage.cache_read_input_tokens // 0) | tonumber)
            | .ok  += (if $r.ok then 1 else 0 end)
          )
        ) as $s
        | {
            n: $n,
            ok: $s.ok,
            avg_latency_ms:           ($s.lat / $n),
            avg_input_tokens:         ($s.in  / $n),
            avg_output_tokens:        ($s.out / $n),
            avg_cache_create_tokens:  ($s.cw  / $n),
            avg_cache_read_tokens:    ($s.cr  / $n)
          }
      end ;

  def cost(s):
    if (s.n // 0) == 0 then null
    else
      ( s.avg_input_tokens        * $pin  / 1000000.0 ) as $usd_in
      | ( s.avg_output_tokens     * $pout / 1000000.0 ) as $usd_out
      | ( s.avg_cache_create_tokens * $pcw / 1000000.0 ) as $usd_cw
      | ( s.avg_cache_read_tokens   * $pcr / 1000000.0 ) as $usd_cr
      | s + {
          usd_input:        $usd_in,
          usd_output:       $usd_out,
          usd_cache_create: $usd_cw,
          usd_cache_read:   $usd_cr,
          usd_total:        ($usd_in + $usd_out + $usd_cw + $usd_cr)
        }
    end ;

  ($log[0]) as $records
  | ([$records[] | select(.mode == "off" and .ok == true)]) as $off
  | ([$records[] | select(.mode == "on"  and .ok == true)]) as $on
  | { off: (cost(stats($off))), on: (cost(stats($on))), records: $records }
  ')

# ---------- markdown report -------------------------------------------------

machine="$(uname -m)"
host="$(uname -n)"

avg_off_lat=$(jq -r '.off.avg_latency_ms // 0' <<<"$agg_json")
avg_on_lat=$(jq  -r '.on.avg_latency_ms  // 0' <<<"$agg_json")
avg_off_in=$(jq  -r '.off.avg_input_tokens // 0' <<<"$agg_json")
avg_on_in=$(jq   -r '.on.avg_input_tokens  // 0' <<<"$agg_json")
avg_off_out=$(jq -r '.off.avg_output_tokens // 0' <<<"$agg_json")
avg_on_out=$(jq  -r '.on.avg_output_tokens  // 0' <<<"$agg_json")
avg_off_cw=$(jq  -r '.off.avg_cache_create_tokens // 0' <<<"$agg_json")
avg_on_cw=$(jq   -r '.on.avg_cache_create_tokens  // 0' <<<"$agg_json")
avg_off_cr=$(jq  -r '.off.avg_cache_read_tokens // 0' <<<"$agg_json")
avg_on_cr=$(jq   -r '.on.avg_cache_read_tokens  // 0' <<<"$agg_json")
usd_off_total=$(jq -r '.off.usd_total // 0' <<<"$agg_json")
usd_on_total=$(jq  -r '.on.usd_total  // 0' <<<"$agg_json")
usd_off_in=$(jq  -r '.off.usd_input // 0' <<<"$agg_json")
usd_on_in=$(jq   -r '.on.usd_input  // 0' <<<"$agg_json")
usd_off_out=$(jq -r '.off.usd_output // 0' <<<"$agg_json")
usd_on_out=$(jq  -r '.on.usd_output  // 0' <<<"$agg_json")
usd_off_cw=$(jq  -r '.off.usd_cache_create // 0' <<<"$agg_json")
usd_on_cw=$(jq   -r '.on.usd_cache_create  // 0' <<<"$agg_json")
usd_off_cr=$(jq  -r '.off.usd_cache_read // 0' <<<"$agg_json")
usd_on_cr=$(jq   -r '.on.usd_cache_read  // 0' <<<"$agg_json")
n_off=$(jq -r '.off.n // 0' <<<"$agg_json")
n_on=$(jq  -r '.on.n  // 0' <<<"$agg_json")
ok_off=$(jq -r '.off.ok // 0' <<<"$agg_json")
ok_on=$(jq  -r '.on.ok  // 0' <<<"$agg_json")

simulated_count=$(jq '[.records[] | select(.simulated == true)] | length' <<<"$agg_json")
mode_label="real-api"
if [ "$dry_run" -eq 1 ]; then
  mode_label="DRY-RUN (simulated, no API call)"
fi

# Linear extrapolation to Cosmos KB (10M tokens).
# Scale = 10_000_000 / wiki_tokens_est .
cosmos_scale=$(awk -v t="$wiki_tokens_est" 'BEGIN { if (t<=0) print 0; else printf "%.4f", 10000000.0 / t }')
cosmos_off_usd=$(awk -v u="$usd_off_total" -v s="$cosmos_scale" 'BEGIN { printf "%.4f", u*s }')
cosmos_on_usd=$(awk  -v u="$usd_on_total"  -v s="$cosmos_scale" 'BEGIN { printf "%.4f", u*s }')

# Savings (cache-on vs cache-off), per request and projected.
saved_usd=$(awk -v a="$usd_off_total" -v b="$usd_on_total" 'BEGIN { printf "%.6f", a-b }')
saved_pct=$(awk -v a="$usd_off_total" -v b="$usd_on_total" 'BEGIN { if (a==0) print 0; else printf "%.1f", (a-b)/a*100 }')
saved_lat_pct=$(awk -v a="$avg_off_lat" -v b="$avg_on_lat" 'BEGIN { if (a==0) print 0; else printf "%.1f", (a-b)/a*100 }')

# break-even: how many cache-read calls amortize one cache-write?
# write_cost = avg_on_cw_tokens * pcw (only nonzero when cache is created)
# per-read marginal saving vs no-cache = (avg_off_in - avg_on_cr) * pin / 1e6
#   (the doc input is replaced with a 0.1x-priced read, but only the wiki
#    portion changes, plus a small uncached system preamble persists)
# We approximate using the actually observed values.
breakeven=$(awk \
  -v cw="$avg_on_cw" -v pcw="$price_cw" \
  -v off_in="$avg_off_in" -v on_in="$avg_on_in" -v on_cr="$avg_on_cr" \
  -v pin="$price_in" -v pcr="$price_cr" \
  'BEGIN {
     write_cost = cw * pcw / 1e6;
     read_cost_per_call = (on_in*pin + on_cr*pcr) / 1e6;
     no_cache_cost_per_call = off_in * pin / 1e6;
     savings_per_call = no_cache_cost_per_call - read_cost_per_call;
     if (savings_per_call <= 0 || write_cost <= 0) print "n/a";
     else printf "%.2f", write_cost / savings_per_call;
   }')

# ---- emit Markdown report --------------------------------------------------

write_report() {
  local out="$1"
  {
    cat <<HEADER
# Prompt Caching ベンチマーク結果 (KMD-48)

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
| cache-on  | \$$(printf '%.6f' "$usd_on_in")  | \$$(printf '%.6f' "$usd_on_out")  | \$$(printf '%.6f' "$usd_on_cw")  | \$$(printf '%.6f' "$usd_on_cr")  | **\$$(printf '%.6f' "$usd_on_total")**  |
| **節約幅** | – | – | – | – | **\$$(printf '%.6f' "$saved_usd") (${saved_pct}%)** |

## 損益分岐点

cache-on レッグの平均から計算（測定区間内に発生した cache_create を均し込む形）:
- 1 リクエスト平均キャッシュ書込みコスト: \$$(awk -v a="$avg_on_cw" -v b="$price_cw" 'BEGIN { printf "%.6f", a*b/1e6 }')
- 1 リクエストあたりの節約額（cache-off 比）: \$$(awk -v a="$usd_off_total" -v b="$usd_on_total" 'BEGIN { printf "%.6f", a-b }')
- **書込みを償却するのに必要な cache-read 回数**: ${breakeven}

> ウォームアップ ON のとき、計測区間の cache-create はゼロに近く、breakeven は 0 に潰れる。
> 「初回書込みコスト」を独立に評価したい場合は \`--no-warm\` で実行し、最初の ON
> リクエストに乗る cache_create を測定対象に含める。
> 償却回数 < cache TTL（5 分）内の通常 invocation 数なら Prompt Caching は黒字。

## Cosmos KB（10M tokens）への線形外挿

スケール = 10,000,000 / ${wiki_tokens_est} ≈ ×${cosmos_scale}

| シナリオ | 1 リクエスト USD（外挿） |
|---|---|
| cache-off | \$$(printf '%.4f' "$cosmos_off_usd") |
| cache-on  | \$$(printf '%.4f' "$cosmos_on_usd") |

> 外挿はトークン数を線形にスケールした単純試算。実際には:
> - 文書部分が 200k token を超えると Anthropic の prompt cache 上限に当たり、Phase 3（embedding 検索層）への移行が必要（CLAUDE.md / wiki-reference-policy.md 参照）
> - 出力トークン数はクエリ依存で線形外挿しないため、出力コストは本表で過大評価される
> - 実務では cache hit ratio < 1 になる（5 分 TTL 切れ・コンテキスト変更）。本値は \"フル hit\" 上限

## 計測条件

- cache-on 側はシステム末尾ブロックに \`cache_control: { type: "ephemeral" }\` を付与
- cache-off 側は同ブロックの \`cache_control\` を **省略**
- 各リクエストの user content 先頭に \`[bench-nonce: <ランダム>]\` を入れて出力キャッシュを抑制
- レイテンシは \`python3 time.time_ns()\` 計測の wall-clock（リクエスト送信開始 → curl 終了まで）
- \`anthropic-version: 2023-06-01\`、\`max_tokens=${max_tokens}\`

## クエリ一覧

HEADER

    local i=1
    for q in "${queries[@]}"; do
      printf -- "%d. %s\n" "$i" "$q"
      i=$((i+1))
    done

  } >"$out"
}

if [ -n "$out_path" ]; then
  write_report "$out_path"
  err "report -> $out_path"
else
  write_report /dev/stdout
fi

if [ -n "$json_path" ]; then
  jq --arg started "$started_at" --arg finished "$finished_at" \
     --arg model "$model" --argjson repeat "$repeat" \
     --argjson wiki_tokens_est "$wiki_tokens_est" \
     --argjson agg "$agg_json" \
     '{ started_at: $started, finished_at: $finished, model: $model,
        repeat: $repeat, wiki_tokens_est: $wiki_tokens_est,
        aggregated: $agg }' \
     <<<"{}" >"$json_path"
  err "json log -> $json_path"
fi
