#!/usr/bin/env bash

set -euo pipefail

passed=0
failed=0

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_SCRIPT="$ROOT_DIR/scripts/wiki/lib/section-context-check.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export PATH="${TMPDIR}:$PATH"

MD_FILE="$TMPDIR/test.md"
OUT_FILE="$TMPDIR/stdout.txt"
ERR_FILE="$TMPDIR/stderr.txt"
ARGS_FILE="$TMPDIR/claude.args"

cat >"$MD_FILE" <<'EOF'
# Test Article

## Overview

This section intentionally needs external context.
EOF

pass() {
  passed=$((passed + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  failed=$((failed + 1))
  printf 'not ok - %s\n' "$1"
}

assert_contains() {
  local label="$1"
  local needle="$2"
  local file="$3"

  if grep -Fq -- "$needle" "$file"; then
    pass "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

assert_not_contains() {
  local label="$1"
  local needle="$2"
  local file="$3"

  if grep -Fq -- "$needle" "$file"; then
    fail "$label (unexpected: $needle)"
  else
    pass "$label"
  fi
}

cat >"$TMPDIR/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$ARGS_FILE"
cat >/dev/null
exit 1
EOF
chmod +x "$TMPDIR/claude"

"$CHECK_SCRIPT" --file "$MD_FILE" --retries 1 >"$OUT_FILE" 2>"$ERR_FILE"

assert_contains "passes allowedTools flag" "--allowedTools" "$ARGS_FILE"
assert_contains "allows python3" "Bash(python3:*)" "$ARGS_FILE"
assert_contains "allows jq" "Bash(jq:*)" "$ARGS_FILE"
assert_contains "allows shasum" "Bash(shasum:*)" "$ARGS_FILE"
assert_contains "allows git rev-parse" "Bash(git rev-parse:*)" "$ARGS_FILE"
assert_contains "allows sed" "Bash(sed:*)" "$ARGS_FILE"
assert_not_contains "does not allow curl" "Bash(curl:*)" "$ARGS_FILE"
assert_not_contains "does not allow ssh" "Bash(ssh:*)" "$ARGS_FILE"
assert_not_contains "does not allow rm" "Bash(rm:*)" "$ARGS_FILE"

printf 'PASSED: %s / FAILED: %s\n' "$passed" "$failed"

if [ "$failed" -gt 0 ]; then
  exit 1
fi
