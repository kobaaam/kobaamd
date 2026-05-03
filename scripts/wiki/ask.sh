#!/usr/bin/env bash
set -euo pipefail

# scripts/wiki/ask.sh
#
# Send the entire kobaamd LLM Wiki (docs/wiki/articles/**/*.md) to the
# Anthropic Messages API together with a query, using Prompt Caching so
# that repeated invocations within the cache TTL hit the cache.
#
# Documents are placed in a static `system` block with
# `cache_control: { type: "ephemeral" }` so that the wiki bytes count once
# per cache window (5 minutes by default). The query lives in the user
# turn and stays uncached.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-ant-... scripts/wiki/ask.sh "<query>"
#   echo "<query>" | scripts/wiki/ask.sh -
#   scripts/wiki/ask.sh --model claude-opus-4-5 "<query>"
#
# Cache hit / miss counters from `usage` are printed to stderr after the
# response; stdout receives only the assistant text.

usage() {
  printf '%s\n' \
    'Usage: ask.sh [options] "<query>"' \
    '       ask.sh [options] -          # read query from stdin' \
    '' \
    'Send docs/wiki/articles/**/*.md to Anthropic Messages API with' \
    'Prompt Caching, then print the assistant reply on stdout.' \
    '' \
    'Options:' \
    '  --model <id>      Anthropic model id (default: $ANTHROPIC_MODEL or claude-opus-4-5)' \
    '  --max-tokens <n>  Output token cap (default: 4096)' \
    '  --include-raw     Forward --include-raw to load_all.sh' \
    '  --raw             Print full JSON response on stdout instead of just the text' \
    '  --retries <n>     Network retry attempts (default: 3)' \
    '  -h, --help        Show this help and exit.' \
    '' \
    'Environment:' \
    '  ANTHROPIC_API_KEY  Required. API key.' \
    '  ANTHROPIC_MODEL    Optional. Overrides the default model.' \
    '  ANTHROPIC_BASE_URL Optional. Defaults to https://api.anthropic.com'
}

err() {
  printf 'ask.sh: %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 1
  fi
}

model="${ANTHROPIC_MODEL:-claude-opus-4-5}"
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
      model="$2"
      shift 2
      ;;
    --max-tokens)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      max_tokens="$2"
      shift 2
      ;;
    --include-raw)
      include_raw=1
      shift
      ;;
    --raw)
      raw_output=1
      shift
      ;;
    --retries)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      retries="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -)
      read_stdin=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      err "unknown option: $1"
      usage >&2
      exit 2
      ;;
    *)
      if [ -z "$query" ]; then
        query="$1"
      else
        err "unexpected positional argument: $1"
        usage >&2
        exit 2
      fi
      shift
      ;;
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

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  err "ANTHROPIC_API_KEY is not set (try: source ~/.zshrc)"
  exit 1
fi

require_cmd jq
require_cmd curl

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

# --- 1. Build the wiki document blob via load_all.sh -------------------------

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

# Forward load_all.sh's stderr (file count / token estimate / warnings) so the
# operator sees them.
if [ -s "$load_log" ]; then
  cat "$load_log" >&2
fi

# --- 2. Build the JSON request payload --------------------------------------

# `system` is an array of content blocks; the wiki blob is a single text block
# tagged with cache_control: ephemeral so the documents are cached.
# The user turn carries the query (uncached).

system_preamble=$'You are a research assistant for the kobaamd project.\nThe document section that follows contains the full LLM Wiki under docs/wiki/articles/.\nAnswer the user query strictly based on this Wiki when possible. If the Wiki is silent, say so explicitly.\nCite the relevant article paths (the `<!-- file: ... -->` markers) when you reference them.'

jq -n \
  --arg model "$model" \
  --argjson max_tokens "$max_tokens" \
  --arg preamble "$system_preamble" \
  --rawfile wiki "$wiki_tmp" \
  --arg query "$query" \
  '{
    model: $model,
    max_tokens: $max_tokens,
    system: [
      { type: "text", text: $preamble },
      {
        type: "text",
        text: ("# kobaamd LLM Wiki (docs/wiki/articles)\n\n" + $wiki),
        cache_control: { type: "ephemeral" }
      }
    ],
    messages: [
      { role: "user", content: $query }
    ]
  }' >"$payload_tmp"

# --- 3. POST with retries ----------------------------------------------------

attempt=0
success=0
last_status=""

while [ "$attempt" -lt "$retries" ]; do
  attempt=$((attempt + 1))

  : >"$response_tmp"
  : >"$http_status_tmp"

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

  last_status=$(cat "$http_status_tmp" 2>/dev/null || echo "")

  if [ "$curl_exit" -eq 0 ] && [ "$last_status" = "200" ]; then
    success=1
    break
  fi

  err "attempt ${attempt}/${retries} failed (curl exit=${curl_exit}, http=${last_status:-unknown})"
  if [ -s "$response_tmp" ]; then
    # Trim binary noise; show at most 2KB of body for diagnostics.
    head -c 2048 "$response_tmp" >&2 || true
    printf '\n' >&2
  fi

  if [ "$attempt" -lt "$retries" ]; then
    # Backoff: 2s, 4s, 8s ...
    sleep_for=$((1 << attempt))
    sleep "$sleep_for"
  fi
done

if [ "$success" -ne 1 ]; then
  err "all ${retries} attempts failed (last http=${last_status:-unknown})"
  exit 1
fi

# --- 4. Surface cache usage to stderr ---------------------------------------

# Anthropic returns usage with input_tokens / output_tokens and (when caching)
# cache_creation_input_tokens / cache_read_input_tokens. Missing fields are
# rendered as 0 by `// 0`.
jq -r '
  .usage // {} | {
    input_tokens: (.input_tokens // 0),
    output_tokens: (.output_tokens // 0),
    cache_creation_input_tokens: (.cache_creation_input_tokens // 0),
    cache_read_input_tokens: (.cache_read_input_tokens // 0)
  } |
  "ask.sh usage: input=\(.input_tokens) output=\(.output_tokens) cache_create=\(.cache_creation_input_tokens) cache_read=\(.cache_read_input_tokens)"
' "$response_tmp" >&2 || true

# --- 5. Emit the assistant text on stdout -----------------------------------

if [ "$raw_output" -eq 1 ]; then
  cat "$response_tmp"
  exit 0
fi

# Concatenate all text blocks from the assistant reply.
text=$(jq -r '
  if (.content | type) == "array" then
    [ .content[] | select(.type == "text") | .text ] | join("\n")
  else
    ""
  end
' "$response_tmp")

if [ -z "$text" ]; then
  err "response contained no text content; re-run with --raw to inspect"
  exit 1
fi

printf '%s\n' "$text"
