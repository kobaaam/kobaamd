#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# scripts/wiki/ask.sh
#
# Codex/Gemini-only wiki Q&A helper. This intentionally replaces the old
# Anthropic Prompt Caching implementation so launchd/autopilot never needs
# ANTHROPIC_API_KEY or Claude.

usage() {
  printf '%s\n' \
    'Usage: ask.sh [options] "<query>"' \
    '       ask.sh [options] -          # read query from stdin' \
    '' \
    'Send docs/wiki/articles/**/*.md to Gemini, then print the reply.' \
    '' \
    'Options:' \
    '  --model <id>      Gemini model id (default: $GEMINI_MODEL or gemini-3.1-pro-preview)' \
    '  --max-tokens <n>  Output token cap (default: 4096)' \
    '  --include-raw     Forward --include-raw to load_all.sh' \
    '  --raw             Print full JSON response on stdout instead of just the text' \
    '  --retries <n>     Network retry attempts (default: 3)' \
    '  -h, --help        Show this help and exit.' \
    '' \
    'Environment:' \
    '  GEMINI_API_KEY    Required. API key. Passed via x-goog-api-key header.' \
    '  GEMINI_MODEL      Optional. Overrides the default model.' \
    '  GEMINI_BASE_URL   Optional. Defaults to https://generativelanguage.googleapis.com' \
    '  ASK_CONTEXT       Optional usage log context (KMD-XX など)'
}

err() { printf 'ask.sh: %s\n' "$*" >&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 1
  fi
}

model="${GEMINI_MODEL:-gemini-3.1-pro-preview}"
max_tokens=4096
include_raw=0
raw_output=0
retries=3
query=""
read_stdin=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      model="$2"; shift 2 ;;
    --max-tokens)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      max_tokens="$2"; shift 2 ;;
    --include-raw)
      include_raw=1; shift ;;
    --raw)
      raw_output=1; shift ;;
    --retries)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      retries="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    -)
      read_stdin=1; shift ;;
    --)
      shift; break ;;
    -*)
      err "unknown option: $1"; usage >&2; exit 2 ;;
    *)
      if [ -z "$query" ]; then
        query="$1"
      else
        err "unexpected positional argument: $1"; usage >&2; exit 2
      fi
      shift ;;
  esac
done

if [ "$#" -gt 0 ] && [ -z "$query" ] && [ "$read_stdin" -eq 0 ]; then
  query="$1"
fi

if [ "$read_stdin" -eq 1 ]; then
  if [ -n "$query" ]; then
    err "cannot combine '-' (stdin) with a positional query"
    exit 2
  fi
  query=$(cat)
fi

if [ -z "$query" ]; then
  err "no query provided"
  usage >&2
  exit 2
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  err "GEMINI_API_KEY is not set"
  exit 1
fi

require_cmd jq
require_cmd curl

if ! git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  err "not in a git repository (run from kobaamd repo)"
  exit 1
fi

load_all="$REPO_ROOT/scripts/wiki/load_all.sh"
if [ ! -x "$load_all" ]; then
  err "scripts/wiki/load_all.sh not found or not executable"
  exit 1
fi

base_url="${GEMINI_BASE_URL:-https://generativelanguage.googleapis.com}"

wiki_tmp=$(mktemp)
load_log=$(mktemp)
payload_tmp=$(mktemp)
response_tmp=$(mktemp)
http_status_tmp=$(mktemp)

cleanup() {
  rm -f "$wiki_tmp" "$load_log" "$payload_tmp" "$response_tmp" "$http_status_tmp"
}
trap cleanup EXIT

load_status=0
if [ "$include_raw" -eq 1 ]; then
  "$load_all" --include-raw >"$wiki_tmp" 2>"$load_log" || load_status=$?
else
  "$load_all" >"$wiki_tmp" 2>"$load_log" || load_status=$?
fi

if [ "$load_status" -ne 0 ]; then
  err "load_all.sh failed (exit=$load_status):"
  cat "$load_log" >&2
  exit 1
fi

if [ -s "$load_log" ]; then
  cat "$load_log" >&2
fi

system_preamble=$'You are a research assistant for the kobaamd project.\nThe document section below contains the full LLM Wiki under docs/wiki/articles/.\nEach article is delimited by an HTML comment marker `<!-- file: <relative-path> -->`.\n\nAnswer strictly based on this Wiki when possible. If the Wiki is silent, say so explicitly.\n\nWhen referencing Wiki content, cite article paths. End with a `## Sources` section listing every article path used.'

jq -n \
  --arg preamble "$system_preamble" \
  --rawfile wiki "$wiki_tmp" \
  --arg query "$query" \
  --argjson max_tokens "$max_tokens" \
  '{
    contents: [
      {
        role: "user",
        parts: [
          {
            text: (
              $preamble
              + "\n\n# kobaamd LLM Wiki (docs/wiki/articles)\n\n"
              + $wiki
              + "\n\n# Query\n\n"
              + $query
            )
          }
        ]
      }
    ],
    generationConfig: {
      maxOutputTokens: $max_tokens,
      temperature: 0.2
    }
  }' >"$payload_tmp"

attempt=0
success=0
last_status=""

while [ "$attempt" -lt "$retries" ]; do
  attempt=$((attempt + 1))
  : >"$response_tmp"
  : >"$http_status_tmp"

  "$REPO_ROOT/scripts/usage/log.sh" gemini "wiki_ask" 0 "${ASK_CONTEXT:-}" || true

  set +e
  curl --silent --show-error --fail-with-body \
    --max-time 180 \
    --output "$response_tmp" \
    --write-out '%{http_code}' \
    -X POST "$base_url/v1beta/models/${model}:generateContent" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -H 'content-type: application/json' \
    --data-binary "@$payload_tmp" \
    >"$http_status_tmp"
  curl_exit=$?
  set -e

  last_status=$(cat "$http_status_tmp" 2>/dev/null || echo "")
  if [ "$curl_exit" -eq 0 ] && [ "$last_status" = "200" ]; then
    success=1
    break
  fi

  err "attempt ${attempt}/${retries} failed (curl exit=${curl_exit}, http=${last_status:-unknown})"
  if [ -s "$response_tmp" ]; then
    head -c 2048 "$response_tmp" >&2 || true
    printf '\n' >&2
  fi

  if [ "$attempt" -lt "$retries" ]; then
    sleep_for=$((1 << attempt))
    sleep "$sleep_for"
  fi
done

if [ "$success" -ne 1 ]; then
  err "all ${retries} attempts failed (last http=${last_status:-unknown})"
  exit 1
fi

jq -r '
  .usageMetadata // {} |
  "ask.sh usage: prompt=\(.promptTokenCount // 0) candidates=\(.candidatesTokenCount // 0) total=\(.totalTokenCount // 0)"
' "$response_tmp" >&2 || true

if [ "$raw_output" -eq 1 ]; then
  cat "$response_tmp"
  exit 0
fi

text=$(jq -r '
  [ .candidates[]?.content.parts[]? | select(.text) | .text ] | join("\n")
' "$response_tmp")

if [ -z "$text" ]; then
  err "response contained no text content; re-run with --raw to inspect"
  exit 1
fi

printf '%s\n' "$text"
