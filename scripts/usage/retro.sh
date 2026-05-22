#!/usr/bin/env bash
# retro.sh — deterministic token-usage retrospective and improvement checklist.
#
# This intentionally does not call an LLM. It creates a compact artifact that a
# weekly Codex/Gemini improvement pass can read only when the metrics justify it.
#
# Usage:
#   scripts/usage/retro.sh [--window-hours N] [--output PATH] [--print]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  printf '%s\n' 'usage: scripts/usage/retro.sh [--window-hours N] [--output PATH] [--print]'
}

die() {
  printf 'usage/retro.sh: %s\n' "$*" >&2
  exit 2
}

window_hours=24
output=""
print_output=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --window-hours)
      [[ $# -ge 2 ]] || die "--window-hours requires a value"
      window_hours="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires a value"
      output="$2"
      shift 2
      ;;
    --print)
      print_output=1
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

if [[ -z "$output" ]]; then
  mkdir -p "$REPO_ROOT/.logs/token-retros"
  output="$REPO_ROOT/.logs/token-retros/$(date -u +%Y%m%dT%H%M%SZ)-${window_hours}h.md"
fi

report_json="$("$SCRIPT_DIR/report.sh" --window-hours "$window_hours" --json)"

generated_at="$(echo "$report_json" | jq -r '.generated_at')"
codex_calls="$(echo "$report_json" | jq -r '.usage.by_api.codex.calls')"
codex_tokens="$(echo "$report_json" | jq -r '.usage.by_api.codex.est_tokens')"
codex_avg="$(echo "$report_json" | jq -r '.derived.codex_avg_tokens_per_call')"
blocked="$(echo "$report_json" | jq -r '.codex_runs.blocked')"
recommendation_count="$(echo "$report_json" | jq -r '.recommendations | length')"

mkdir -p "$(dirname "$output")"

{
  printf '# Token Usage Retrospective\n\n'
  printf -- '- Generated: `%s`\n' "$generated_at"
  printf -- '- Window: `%s` hours\n' "$window_hours"
  printf -- '- Codex calls: `%s`\n' "$codex_calls"
  printf -- '- Codex estimated tokens: `%s`\n' "$codex_tokens"
  printf -- '- Codex average tokens/call: `%s`\n' "$codex_avg"
  printf -- '- Codex blocked events: `%s`\n\n' "$blocked"

  printf '## Observations\n\n'
  if [[ "$codex_calls" -eq 0 ]]; then
    printf -- '- No Codex calls were recorded in this window.\n'
  else
    printf -- '- Codex usage was concentrated in these bundle/type records:\n'
    echo "$report_json" | jq -r '
      if (.usage.top_codex_types | length) == 0 then
        "- No token-bearing Codex type records were available."
      else
        .usage.top_codex_types[]
        | "  - \(.type): calls=\(.calls), est_tokens=\(.est_tokens), contexts=\(.contexts | join(","))"
      end
    '
  fi
  if [[ "$blocked" -gt 0 ]]; then
    printf -- '- At least one blocked/rate-limit Codex event occurred in this window.\n'
  fi
  printf '\n'

  printf '## Recommended Improvements\n\n'
  if [[ "$recommendation_count" -eq 0 ]]; then
    printf -- '- No automatic improvement required for this window.\n'
  else
    echo "$report_json" | jq -r '.recommendations[] | "- \(.)"'
  fi
  printf '\n'

  printf '## Action Checklist\n\n'
  printf -- '- [ ] Keep `scripts/launchd/run_bundle.sh` usage guard enabled.\n'
  printf -- '- [ ] If Codex average tokens/call is high, inspect recent `.logs/kobaamd_pipeline_*.log` for full-file reads or pasted diffs.\n'
  printf -- '- [ ] If a single bundle dominates tokens, lower `KOBAAMD_CODEX_MODEL_*` or split that workflow into shell-first preflight plus LLM-only review.\n'
  printf -- '- [ ] If blocked events occurred, leave non-critical Todo work for the next window and only process `Reviewed` / `Human in Review` items.\n'
  printf '\n'

  printf '## Raw Report\n\n'
  printf '```json\n'
  printf '%s\n' "$report_json"
  printf '```\n'
} > "$output"

if [[ "$print_output" == "1" ]]; then
  cat "$output"
else
  printf '%s\n' "$output"
fi
