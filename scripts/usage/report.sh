#!/usr/bin/env bash
# report.sh — token/call usage report for kobaamd automation.
#
# Usage:
#   scripts/usage/report.sh [--window-hours N] [--json]
#
# Reads:
#   .logs/api_usage.jsonl   — call/token estimates written by scripts/usage/log.sh
#   .logs/codex_runs.jsonl  — Codex run outcomes written by scripts/codex/run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
API_LOG="${REPO_ROOT}/.logs/api_usage.jsonl"
CODEX_RUN_LOG="${REPO_ROOT}/.logs/codex_runs.jsonl"

usage() {
  printf '%s\n' 'usage: scripts/usage/report.sh [--window-hours N] [--json]'
}

die() {
  printf 'usage/report.sh: %s\n' "$*" >&2
  exit 2
}

window_hours=24
json_output=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --window-hours)
      [[ $# -ge 2 ]] || die "--window-hours requires a value"
      window_hours="$2"
      shift 2
      ;;
    --json)
      json_output=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$window_hours" =~ ^[0-9]+$ ]] || die "--window-hours must be a non-negative integer"
command -v jq >/dev/null 2>&1 || die "jq is required"

now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
now_epoch="$(date -u +%s)"
window_start_epoch=$((now_epoch - (window_hours * 3600)))
window_start_iso="$(date -u -r "$window_start_epoch" +%Y-%m-%dT%H:%M:%SZ)"

codex_token_warn="${TOKEN_REPORT_CODEX_TOKEN_WARN:-300000}"
codex_avg_warn="${TOKEN_REPORT_CODEX_AVG_WARN:-120000}"
codex_call_warn="${TOKEN_REPORT_CODEX_CALL_WARN:-35}"

[[ "$codex_token_warn" =~ ^[0-9]+$ ]] || die "TOKEN_REPORT_CODEX_TOKEN_WARN must be numeric"
[[ "$codex_avg_warn" =~ ^[0-9]+$ ]] || die "TOKEN_REPORT_CODEX_AVG_WARN must be numeric"
[[ "$codex_call_warn" =~ ^[0-9]+$ ]] || die "TOKEN_REPORT_CODEX_CALL_WARN must be numeric"

usage_json="$(
  if [[ -r "$API_LOG" ]]; then
    jq -s \
      --argjson window_hours "$window_hours" \
      --argjson window_start_epoch "$window_start_epoch" '
        def recent:
          [
            .[]
            | select(type == "object")
            | select(.ts? and .api?)
            | select((.ts | fromdateiso8601) >= $window_start_epoch)
          ];
        def api_stats($records; $api):
          {
            calls: ([$records[] | select(.api == $api)] | length),
            est_tokens: ([$records[] | select(.api == $api) | (.est_tokens // 0)] | add // 0)
          };
        recent as $records
        | {
            window_hours: $window_hours,
            by_api: {
              claude: api_stats($records; "claude"),
              codex: api_stats($records; "codex"),
              gemini: api_stats($records; "gemini")
            },
            top_codex_types: (
              [$records[] | select(.api == "codex") | {type: (.type // "unknown"), context: (.context // ""), est_tokens: (.est_tokens // 0)}]
              | sort_by(.type)
              | group_by(.type)
              | map({
                  type: .[0].type,
                  calls: length,
                  est_tokens: (map(.est_tokens) | add // 0),
                  contexts: (map(.context) | unique | map(select(. != "")) | .[0:5])
                })
              | sort_by(-.est_tokens, -.calls)
              | .[0:8]
            )
          }
      ' "$API_LOG"
  else
    jq -n --argjson window_hours "$window_hours" \
      '{window_hours: $window_hours, by_api:{claude:{calls:0,est_tokens:0}, codex:{calls:0,est_tokens:0}, gemini:{calls:0,est_tokens:0}}, top_codex_types:[]}'
  fi
)"

codex_runs_json="$(
  if [[ -r "$CODEX_RUN_LOG" ]]; then
    jq -s --argjson window_start_epoch "$window_start_epoch" '
      [
        .[]
        | select(type == "object")
        | select(.ts?)
        | select((.ts | fromdateiso8601) >= $window_start_epoch)
      ] as $records
      | {
          calls: ($records | length),
          failures: ([$records[] | select((.exit_code // 0) != 0)] | length),
          blocked: ([$records[] | select((.blocked // "") != "")] | length),
          last_blocked: ([$records[] | select((.blocked // "") != "")] | last // null)
        }
    ' "$CODEX_RUN_LOG"
  else
    jq -n '{calls:0, failures:0, blocked:0, last_blocked:null}'
  fi
)"

report_json="$(
  jq -n \
    --arg generated_at "$now_iso" \
    --arg window_start "$window_start_iso" \
    --argjson window_hours "$window_hours" \
    --argjson usage "$usage_json" \
    --argjson codex_runs "$codex_runs_json" \
    --argjson codex_token_warn "$codex_token_warn" \
    --argjson codex_avg_warn "$codex_avg_warn" \
    --argjson codex_call_warn "$codex_call_warn" '
      ($usage.by_api.codex.est_tokens // 0) as $codex_tokens
      | ($usage.by_api.codex.calls // 0) as $codex_calls
      | (if $codex_calls > 0 then (($codex_tokens / $codex_calls) | floor) else 0 end) as $codex_avg
      | {
          generated_at: $generated_at,
          window_hours: $window_hours,
          window_start: $window_start,
          usage: $usage,
          codex_runs: $codex_runs,
          derived: {
            codex_avg_tokens_per_call: $codex_avg,
            thresholds: {
              codex_token_warn: $codex_token_warn,
              codex_avg_warn: $codex_avg_warn,
              codex_call_warn: $codex_call_warn
            }
          },
          recommendations: (
            [
              if $codex_calls > $codex_call_warn
              then "Codex call count is high; keep launchd usage guard enabled and defer phase-B implementation when possible."
              else empty end,
              if $codex_tokens > $codex_token_warn
              then "Codex token use is high; inspect top_codex_types and reduce prompt/log/diff payloads for the largest bundle."
              else empty end,
              if $codex_avg > $codex_avg_warn
              then "Average tokens per Codex call is high; prefer targeted rg/sed reads and avoid full AGENTS/docs/log loading."
              else empty end,
              if ($codex_runs.blocked // 0) > 0
              then "Recent Codex blocked/rate-limit events exist; skip non-critical active work until the next window."
              else empty end
            ]
          )
        }
    '
)"

if [[ "$json_output" == "1" ]]; then
  printf '%s\n' "$report_json"
  exit 0
fi

printf '# Token Usage Report\n\n'
printf -- '- Generated: `%s`\n' "$(echo "$report_json" | jq -r '.generated_at')"
printf -- '- Window: last `%s` hours, since `%s`\n\n' "$window_hours" "$window_start_iso"

printf '## API Calls And Tokens\n\n'
printf '| API | Calls | Estimated tokens |\n'
printf '|---|---:|---:|\n'
echo "$report_json" | jq -r '
  .usage.by_api
  | to_entries[]
  | "| \(.key) | \(.value.calls) | \(.value.est_tokens) |"
'

printf '\n## Codex Run Outcomes\n\n'
echo "$report_json" | jq -r '
  .codex_runs
  | "- Calls recorded: `\(.calls)`\n- Failures: `\(.failures)`\n- Blocked/rate-limit events: `\(.blocked)`"
'

printf '\n## Top Codex Bundles\n\n'
if [[ "$(echo "$report_json" | jq '.usage.top_codex_types | length')" -eq 0 ]]; then
  printf 'No Codex token records in this window.\n'
else
  printf '| Type | Calls | Estimated tokens | Contexts |\n'
  printf '|---|---:|---:|---|\n'
  echo "$report_json" | jq -r '
    .usage.top_codex_types[]
    | "| \(.type) | \(.calls) | \(.est_tokens) | \(.contexts | join(", ")) |"
  '
fi

printf '\n## Recommendations\n\n'
if [[ "$(echo "$report_json" | jq '.recommendations | length')" -eq 0 ]]; then
  printf 'No automatic recommendations for this window.\n'
else
  echo "$report_json" | jq -r '.recommendations[] | "- \(.)"'
fi
