#!/usr/bin/env bash
# check.sh — API usage window aggregation for kobaamd pipeline.
#
# Reads .logs/api_usage.jsonl, aggregates the last N hours, and reports
# whether any API exceeded its call-count threshold.
#
# Usage:
#   scripts/usage/check.sh [--window-hours N] [--json]
#
# Exit codes:
#   0   all APIs are within threshold
#   10  one or more APIs exceeded threshold
#   2   invalid arguments, read failure, or aggregation failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${REPO_ROOT}/.logs/api_usage.jsonl"

usage() {
  printf '%s\n' 'usage: scripts/usage/check.sh [--window-hours N] [--json]'
}

die2() {
  printf 'usage/check.sh: %s\n' "$*" >&2
  exit 2
}

window_hours=5
json_output=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --window-hours)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
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

[[ "$window_hours" =~ ^[0-9]+$ ]] || die2 "--window-hours must be a non-negative integer"

threshold_claude="${USAGE_THRESHOLD_CLAUDE:-100}"
threshold_codex="${USAGE_THRESHOLD_CODEX:-50}"
threshold_gemini="${USAGE_THRESHOLD_GEMINI:-30}"

for threshold in "$threshold_claude" "$threshold_codex" "$threshold_gemini"; do
  [[ "$threshold" =~ ^[0-9]+$ ]] || die2 "thresholds must be non-negative integers"
done

command -v jq >/dev/null 2>&1 || die2 "jq is required"
[[ -r "$LOG_FILE" ]] || die2 "log file not readable: $LOG_FILE"

now_epoch="$(date -u +%s)"
window_start_epoch=$((now_epoch - (window_hours * 3600)))

json_result="$(
  jq -s \
    --argjson window_hours "$window_hours" \
    --argjson window_start_epoch "$window_start_epoch" \
    --argjson threshold_claude "$threshold_claude" \
    --argjson threshold_codex "$threshold_codex" \
    --argjson threshold_gemini "$threshold_gemini" '
      def api_stats($records; $name):
        {
          calls: ([$records[] | select(.api == $name)] | length),
          est_tokens: ([$records[] | select(.api == $name) | (.est_tokens // 0)] | add // 0)
        };

      [
        .[]
        | select(type == "object")
        | select(.ts? and .api?)
        | select((.ts | fromdateiso8601) >= $window_start_epoch)
      ] as $recent
      | {
          window_hours: $window_hours,
          window_start: ($window_start_epoch | todateiso8601),
          claude: api_stats($recent; "claude"),
          codex: api_stats($recent; "codex"),
          gemini: api_stats($recent; "gemini"),
          thresholds: {
            claude: $threshold_claude,
            codex: $threshold_codex,
            gemini: $threshold_gemini
          }
        }
      | .exceeded = (
          [
            if .claude.calls > .thresholds.claude then "claude" else empty end,
            if .codex.calls > .thresholds.codex then "codex" else empty end,
            if .gemini.calls > .thresholds.gemini then "gemini" else empty end
          ]
        )
    ' "$LOG_FILE"
)" || die2 "failed to aggregate usage log"

if [[ "$json_output" == "1" ]]; then
  printf '%s\n' "$json_result"
else
  printf 'claude=%s codex=%s gemini=%s window_hours=%s\n' \
    "$(echo "$json_result" | jq -r '.claude.calls')" \
    "$(echo "$json_result" | jq -r '.codex.calls')" \
    "$(echo "$json_result" | jq -r '.gemini.calls')" \
    "$(echo "$json_result" | jq -r '.window_hours')"
fi

if [[ "$(echo "$json_result" | jq -r '.exceeded | length')" -gt 0 ]]; then
  exit 10
fi

exit 0
