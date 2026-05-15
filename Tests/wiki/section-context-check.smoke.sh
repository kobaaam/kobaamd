#!/usr/bin/env bash

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

cat >"$MD_FILE" <<'EOF'
# Test Article

## Overview

This section intentionally needs external context.

### Details

More section text.
EOF

pass() {
  passed=$((passed + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  failed=$((failed + 1))
  printf 'not ok - %s\n' "$1"
}

assert_eq() {
  label="$1"
  expected="$2"
  actual="$3"

  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label (expected: $expected, actual: $actual)"
  fi
}

assert_contains() {
  label="$1"
  needle="$2"
  file="$3"

  if grep -Fq "$needle" "$file"; then
    pass "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

assert_not_contains() {
  label="$1"
  needle="$2"
  file="$3"

  if grep -Fq "$needle" "$file"; then
    fail "$label (unexpected: $needle)"
  else
    pass "$label"
  fi
}

assert_empty() {
  label="$1"
  file="$2"

  if [ ! -s "$file" ]; then
    pass "$label"
  else
    fail "$label (file is not empty)"
  fi
}

write_success_mock() {
  cat >"$TMPDIR/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' '{"hash":"abc123","verdict":"NO: 外部文脈が必要"}'
printf '%s\n' '[mock claude] WARN: something' >&2
exit 0
EOF
  chmod +x "$TMPDIR/claude"
}

write_failure_mock() {
  cat >"$TMPDIR/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' '[mock claude] ERROR: agent failed' >&2
exit 1
EOF
  chmod +x "$TMPDIR/claude"
}

# Test 1: successful subagent call keeps stdout NDJSON-only and relays stderr.
write_success_mock
: >"$OUT_FILE"
: >"$ERR_FILE"
"$CHECK_SCRIPT" --file "$MD_FILE" >"$OUT_FILE" 2>"$ERR_FILE"
rc=$?

assert_eq "success path exits 0" "0" "$rc"
assert_contains "success path emits violation NDJSON" '"rule":"section-context-missing"' "$OUT_FILE"
assert_contains "success path relays mock stderr" "[mock claude] WARN:" "$ERR_FILE"
assert_not_contains "success path does not mix stderr into stdout" "[mock claude] WARN:" "$OUT_FILE"

if awk 'NF { print }' "$OUT_FILE" | while IFS= read -r line; do printf '%s\n' "$line" | jq -e . >/dev/null 2>&1 || exit 1; done; then
  pass "success path stdout is valid NDJSON"
else
  fail "success path stdout is valid NDJSON"
fi

# Test 2: failed subagent attempts are skipped after retries, stderr is relayed, stdout stays empty.
write_failure_mock
: >"$OUT_FILE"
: >"$ERR_FILE"
"$CHECK_SCRIPT" --file "$MD_FILE" --retries 2 >"$OUT_FILE" 2>"$ERR_FILE"
rc=$?

assert_eq "failure path exits 0 as skip" "0" "$rc"
assert_contains "failure path reports all attempts failed" "WARN: all 2 subagent attempts failed" "$ERR_FILE"
assert_contains "failure path relays mock error stderr" "[mock claude] ERROR:" "$ERR_FILE"
assert_empty "failure path emits no stdout" "$OUT_FILE"

printf 'PASSED: %s / FAILED: %s\n' "$passed" "$failed"

if [ "$failed" -gt 0 ]; then
  exit 1
fi

exit 0
