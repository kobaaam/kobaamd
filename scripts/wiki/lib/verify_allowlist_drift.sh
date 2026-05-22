#!/usr/bin/env bash
# verify_allowlist_drift.sh — ensure section-context-check allowlist stays in sync

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SHELL_FILE="$ROOT/scripts/wiki/lib/section-context-check.sh"
AGENT_FILE="$ROOT/.claude/agents/kobaamd_lint_section_context.md"
WIKI_FILE="$ROOT/docs/wiki/articles/practices/wiki-reference-policy.md"

usage() {
  cat <<'EOF' >&2
Usage: scripts/wiki/lib/verify_allowlist_drift.sh [--shell-file <path>] [--agent-file <path>] [--wiki-file <path>]
EOF
}

error() {
  printf 'verify_allowlist_drift: %s\n' "$*" >&2
  exit 2
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

canonicalize_csv() {
  local raw="$1"
  printf '%s' "$raw" \
    | tr ',' '\n' \
    | sed 's/`//g' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | awk 'NF' \
    | LC_ALL=C sort -u
}

extract_shell_allowlist() {
  sed -n '/local -a allowed_tools=(/,/^[[:space:]]*)/p' "$1" \
    | grep 'Bash(' \
    | sed -E 's/.*Bash\(([^:]*):\*\).*/\1/' \
    | LC_ALL=C sort -u
}

extract_canonical_line() {
  local file="$1"
  local line
  line=$(grep -F 'Canonical allowlist:' "$file" | head -n 1 || true)
  [ -n "$line" ] || error "missing 'Canonical allowlist:' in $file"
  canonicalize_csv "${line#*Canonical allowlist: }"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --shell-file)
        SHELL_FILE="$2"
        shift 2
        ;;
      --agent-file)
        AGENT_FILE="$2"
        shift 2
        ;;
      --wiki-file)
        WIKI_FILE="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        usage
        error "unknown option: $1"
        ;;
    esac
  done
}

compare_lists() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" != "$actual" ]; then
    printf 'verify_allowlist_drift: %s mismatch\n' "$label" >&2
    printf 'expected:\n%s\n' "$expected" >&2
    printf 'actual:\n%s\n' "$actual" >&2
    return 1
  fi
  return 0
}

main() {
  parse_args "$@"

  [ -f "$SHELL_FILE" ] || error "shell file not found: $SHELL_FILE"
  [ -f "$AGENT_FILE" ] || error "agent file not found: $AGENT_FILE"
  [ -f "$WIKI_FILE" ] || error "wiki file not found: $WIKI_FILE"

  local shell_list agent_list wiki_list
  shell_list="$(extract_shell_allowlist "$SHELL_FILE")"
  [ -n "$shell_list" ] || error "failed to extract allowlist from $SHELL_FILE"
  agent_list="$(extract_canonical_line "$AGENT_FILE")"
  wiki_list="$(extract_canonical_line "$WIKI_FILE")"

  compare_lists "$AGENT_FILE" "$shell_list" "$agent_list"
  compare_lists "$WIKI_FILE" "$shell_list" "$wiki_list"

  printf 'verify_allowlist_drift: OK\n'
}

main "$@"
