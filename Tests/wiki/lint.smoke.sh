#!/usr/bin/env bash

passed=0
failed=0

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LINT_SCRIPT="$ROOT_DIR/scripts/wiki/lint.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TARGET_FILE="$ROOT_DIR/docs/wiki/articles/components/file-tree-outline-sync.md"
REPORT_FILE="$TMPDIR/lint-report.json"
STDOUT_FILE="$TMPDIR/stdout.txt"
STDERR_FILE="$TMPDIR/stderr.txt"

pass() {
  passed=$((passed + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  failed=$((failed + 1))
  printf 'not ok - %s\n' "$1"
}

assert_eq() {
  local got="$1"
  local expected="$2"
  local name="$3"
  if [ "$got" = "$expected" ]; then
    pass "$name"
  else
    fail "$name (expected '$expected', got '$got')"
  fi
}

assert_ne() {
  local got="$1"
  local not_expected="$2"
  local name="$3"
  if [ "$got" != "$not_expected" ]; then
    pass "$name"
  else
    fail "$name (unexpected '$got')"
  fi
}

assert_file() {
  local path="$1"
  local name="$2"
  if [ -f "$path" ]; then
    pass "$name"
  else
    fail "$name (missing file: $path)"
  fi
}

bash "$LINT_SCRIPT" --no-llm --report "$REPORT_FILE" "$TARGET_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE"
rc=$?

assert_ne "$rc" "2" "lint smoke should not fail internally"
assert_file "$REPORT_FILE" "execution report should be written"

section_status="$(jq -r '.rules.section_context.status' "$REPORT_FILE")"
section_reason="$(jq -r '.rules.section_context.reason' "$REPORT_FILE")"
section_attempted="$(jq -r '.rules.section_context.attempted_files' "$REPORT_FILE")"
section_skipped="$(jq -r '.rules.section_context.skipped_files' "$REPORT_FILE")"
frontmatter_status="$(jq -r '.rules.frontmatter.status' "$REPORT_FILE")"
stale_status="$(jq -r '.rules.stale.status' "$REPORT_FILE")"

assert_eq "$frontmatter_status" "executed" "frontmatter rule should be recorded as executed"
assert_eq "$stale_status" "executed" "stale rule should be recorded as executed"
assert_eq "$section_status" "skipped" "section-context should be recorded as skipped under --no-llm"
assert_eq "$section_reason" "no_llm" "section-context skip reason should be explicit"
assert_eq "$section_attempted" "1" "section-context should record attempted file count"
assert_eq "$section_skipped" "1" "section-context should record skipped file count"

if grep -q 'unbound variable' "$STDERR_FILE"; then
  fail "stderr should not contain unbound variable"
else
  pass "stderr should not contain unbound variable"
fi

if [ "$failed" -gt 0 ]; then
  printf '%s tests failed\n' "$failed"
  exit 1
fi

printf 'all %s tests passed\n' "$passed"
