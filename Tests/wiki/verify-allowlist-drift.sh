#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VERIFY_SCRIPT="$ROOT_DIR/scripts/wiki/lib/verify_allowlist_drift.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1"
  exit 1
}

cat >"$TMPDIR/section-context-check.sh" <<'EOF'
local -a allowed_tools=(
  "Read"
  "Bash(python3:*)"
  "Bash(jq:*)"
  "Bash(shasum:*)"
)
EOF

cat >"$TMPDIR/agent.md" <<'EOF'
Canonical allowlist: `python3`, `jq`, `shasum`
EOF

cat >"$TMPDIR/wiki.md" <<'EOF'
Canonical allowlist: `python3`, `jq`, `shasum`
EOF

if "$VERIFY_SCRIPT" \
  --shell-file "$TMPDIR/section-context-check.sh" \
  --agent-file "$TMPDIR/agent.md" \
  --wiki-file "$TMPDIR/wiki.md" >/dev/null 2>&1; then
  pass "matching fixtures pass"
else
  fail "matching fixtures pass"
fi

cat >"$TMPDIR/wiki-drift.md" <<'EOF'
Canonical allowlist: `python3`, `jq`, `curl`
EOF

if "$VERIFY_SCRIPT" \
  --shell-file "$TMPDIR/section-context-check.sh" \
  --agent-file "$TMPDIR/agent.md" \
  --wiki-file "$TMPDIR/wiki-drift.md" >/dev/null 2>&1; then
  fail "drift fixture fails"
else
  pass "drift fixture fails"
fi
