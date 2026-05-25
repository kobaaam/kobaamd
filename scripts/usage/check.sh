#!/usr/bin/env bash
# check.sh — API usage window aggregation for kobaamd pipeline.
#
# Reads .logs/api_usage.jsonl, aggregates the last N hours, and reports
# whether any API exceeded its call-count threshold. Malformed lines are
# skipped with a warning so partial log corruption does not stop the pipeline.
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
LOG_FILE="${USAGE_LOG_FILE:-${REPO_ROOT}/.logs/api_usage.jsonl}"

usage() {
  printf '%s\n' 'usage: scripts/usage/check.sh [--window-hours N] [--json]'
}

die2() {
  printf 'usage/check.sh: %s\n' "$*" >&2
  exit 2
}

warn() {
  printf 'usage/check.sh: WARN: %s\n' "$*" >&2
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

claude_calls=0
claude_tokens=0
codex_calls=0
codex_tokens=0
gemini_calls=0
gemini_tokens=0
line_no=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))
  [[ -n "$line" ]] || continue

  if ! printf '%s\n' "$line" | jq -e 'select(type == "object")' >/dev/null 2>&1; then
    warn "skipping invalid JSON object at line ${line_no}"
    continue
  fi

  if ! api="$(printf '%s\n' "$line" | jq -er '(.api // empty) | strings | select(length > 0)' 2>/dev/null)"; then
    warn "skipping record with invalid api at line ${line_no}"
    continue
  fi

  if ! ts="$(printf '%s\n' "$line" | jq -er '(.ts // empty) | strings | select(length > 0)' 2>/dev/null)"; then
    warn "skipping record with invalid ts at line ${line_no}"
    continue
  fi

  if ! ts_epoch="$(jq -nr --arg ts "$ts" '$ts | fromdateiso8601' 2>/dev/null)"; then
    warn "skipping record with unparseable ts at line ${line_no}: ${ts}"
    continue
  fi

  (( ts_epoch >= window_start_epoch )) || continue

  est_tokens="$(printf '%s\n' "$line" | jq -r '
    (.est_tokens // 0)
    | if type == "number" then floor
      elif type == "string" and test("^[0-9]+$") then tonumber
      else 0
      end
  ' 2>/dev/null || printf '0')"

  case "$api" in
    claude)
      claude_calls=$((claude_calls + 1))
      claude_tokens=$((claude_tokens + est_tokens))
      ;;
    codex)
      codex_calls=$((codex_calls + 1))
      codex_tokens=$((codex_tokens + est_tokens))
      ;;
    gemini)
      gemini_calls=$((gemini_calls + 1))
      gemini_tokens=$((gemini_tokens + est_tokens))
      ;;
    *)
      warn "skipping record with unknown api at line ${line_no}: ${api}"
      ;;
  esac
done < "$LOG_FILE"

window_start_iso="$(
  jq -nr --argjson epoch "$window_start_epoch" '$epoch | todateiso8601'
)" || die2 "failed to format window start"

json_result="$(
  jq -nc \
    --argjson window_hours "$window_hours" \
    --arg window_start "$window_start_iso" \
    --argjson threshold_claude "$threshold_claude" \
    --argjson threshold_codex "$threshold_codex" \
    --argjson threshold_gemini "$threshold_gemini" \
    --argjson claude_calls "$claude_calls" \
    --argjson claude_tokens "$claude_tokens" \
    --argjson codex_calls "$codex_calls" \
    --argjson codex_tokens "$codex_tokens" \
    --argjson gemini_calls "$gemini_calls" \
    --argjson gemini_tokens "$gemini_tokens" '
      {
        window_hours: $window_hours,
        window_start: $window_start,
        claude: {
          calls: $claude_calls,
          est_tokens: $claude_tokens
        },
        codex: {
          calls: $codex_calls,
          est_tokens: $codex_tokens
        },
        gemini: {
          calls: $gemini_calls,
          est_tokens: $gemini_tokens
        },
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
    '
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
