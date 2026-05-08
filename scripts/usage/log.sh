#!/usr/bin/env bash
# log.sh — API usage append helper for kobaamd pipeline.
#
# Phase 1 では呼び出し回数のみ集計し、est_tokens は将来用に記録する。
#
# Usage:
#   scripts/usage/log.sh <api> <type> [est_tokens] [context]
#     api:        claude | codex | gemini
#     type:       自由文（subagent 名、command 名、manual など）
#     est_tokens: 整数（未指定は 0）
#     context:    自由文（KMD-XX など）
#
# どの失敗でも親プロセスを止めないため、警告を stderr に出して exit 0 で終わる。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/.logs"
LOG_FILE="${LOG_DIR}/api_usage.jsonl"

warn() {
  printf 'usage/log.sh: %s\n' "$*" >&2
}

usage() {
  printf '%s\n' \
    'usage: scripts/usage/log.sh <api> <type> [est_tokens] [context]' \
    '  api:        claude | codex | gemini' \
    '  type:       自由文（subagent 名、command 名、manual など）' \
    '  est_tokens: 整数（未指定は 0）' \
    '  context:    自由文（KMD-XX など）'
}

safe_main() {
  local api="${1:-}"
  local type="${2:-}"
  local est_tokens="${3:-0}"
  local context="${4:-}"
  local record=""

  if [[ -z "$api" || -z "$type" ]]; then
    usage >&2
    return 1
  fi

  case "$api" in
    claude|codex|gemini) ;;
    *)
      warn "unknown api: $api"
      return 1
      ;;
  esac

  if [[ ! "$est_tokens" =~ ^[0-9]+$ ]]; then
    warn "est_tokens must be a non-negative integer: $est_tokens"
    return 1
  fi

  command -v jq >/dev/null 2>&1 || {
    warn "jq is required"
    return 1
  }

  mkdir -p "$LOG_DIR"

  record=$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg api "$api" \
    --arg type "$type" \
    --argjson est_tokens "$est_tokens" \
    --arg context "$context" \
    '{ts:$ts, api:$api, type:$type, est_tokens:$est_tokens, context:$context}')

  printf '%s\n' "$record" >> "$LOG_FILE"
}

if ! safe_main "$@"; then
  warn "usage record was not written"
fi

exit 0
