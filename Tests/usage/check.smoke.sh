#!/usr/bin/env bash

set -euo pipefail

passed=0
failed=0

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_SCRIPT="$ROOT_DIR/scripts/usage/check.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

OUT_FILE="$TMPDIR/stdout.txt"
ERR_FILE="$TMPDIR/stderr.txt"

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

assert_empty() {
  label="$1"
  file="$2"

  if [ ! -s "$file" ]; then
    pass "$label"
  else
    fail "$label (file is not empty)"
  fi
}

assert_json_expr() {
  label="$1"
  file="$2"
  expr="$3"

  if jq -e "$expr" "$file" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label (expr failed: $expr)"
  fi
}

iso_hours_ago() {
  python3 - "$1" <<'PY'
import datetime
import sys

hours = int(sys.argv[1])
dt = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
print(dt.replace(microsecond=0).isoformat().replace("+00:00", "Z"))
PY
}

run_check() {
  local log_file="$1"
  shift

  : >"$OUT_FILE"
  : >"$ERR_FILE"

  set +e
  env "USAGE_LOG_FILE=$log_file" "$@" "$CHECK_SCRIPT" --window-hours 5 --json >"$OUT_FILE" 2>"$ERR_FILE"
  rc=$?
  set -e
}

# Test 1: normal aggregation counts only records inside the time window.
LOG_NORMAL="$TMPDIR/normal.jsonl"
cat >"$LOG_NORMAL" <<EOF
{"ts":"$(iso_hours_ago 1)","api":"codex","type":"bundle","est_tokens":12,"context":"kobaamd_pipeline_active"}
{"ts":"$(iso_hours_ago 2)","api":"gemini","type":"review","est_tokens":34,"context":"KMD-176"}
{"ts":"$(iso_hours_ago 8)","api":"claude","type":"old","est_tokens":99,"context":"KMD-176"}
EOF

run_check "$LOG_NORMAL"
assert_eq "normal aggregation exits 0" "0" "$rc"
assert_json_expr "normal aggregation counts recent codex only" "$OUT_FILE" '.codex.calls == 1 and .codex.est_tokens == 12'
assert_json_expr "normal aggregation excludes old claude record" "$OUT_FILE" '.claude.calls == 0 and .claude.est_tokens == 0'
assert_json_expr "normal aggregation counts recent gemini record" "$OUT_FILE" '.gemini.calls == 1 and .gemini.est_tokens == 34'
assert_json_expr "normal aggregation has no exceeded APIs" "$OUT_FILE" '(.exceeded | length) == 0'
assert_empty "normal aggregation emits no warnings" "$ERR_FILE"

# Test 2: threshold exceed returns exit 10 and reports the exceeded API.
LOG_THRESHOLD="$TMPDIR/threshold.jsonl"
cat >"$LOG_THRESHOLD" <<EOF
{"ts":"$(iso_hours_ago 1)","api":"codex","type":"bundle","est_tokens":10,"context":"a"}
EOF

run_check "$LOG_THRESHOLD" "USAGE_THRESHOLD_CODEX=0"
assert_eq "threshold exceed exits 10" "10" "$rc"
assert_json_expr "threshold exceed reports codex" "$OUT_FILE" '.exceeded == ["codex"]'

# Test 3: missing log file fails with exit 2.
run_check "$TMPDIR/missing.jsonl"
assert_eq "missing log exits 2" "2" "$rc"
assert_contains "missing log explains unreadable file" "log file not readable" "$ERR_FILE"

# Test 4: empty log is a valid zero-count result.
LOG_EMPTY="$TMPDIR/empty.jsonl"
: >"$LOG_EMPTY"
run_check "$LOG_EMPTY"
assert_eq "empty log exits 0" "0" "$rc"
assert_json_expr "empty log yields zero counts" "$OUT_FILE" '.claude.calls == 0 and .codex.calls == 0 and .gemini.calls == 0'
assert_empty "empty log emits no warnings" "$ERR_FILE"

# Test 5: malformed lines are skipped with warnings while valid records still count.
LOG_MIXED="$TMPDIR/mixed.jsonl"
cat >"$LOG_MIXED" <<EOF
{"ts":"$(iso_hours_ago 1)","api":"codex","type":"bundle","est_tokens":7,"context":"ok"}
{not json
{"ts":"not-a-time","api":"codex","type":"bundle","est_tokens":100,"context":"bad-ts"}
{"ts":"$(iso_hours_ago 1)","api":"","type":"bundle","est_tokens":1,"context":"bad-api"}
{"ts":"$(iso_hours_ago 1)","api":"gemini","type":"review","est_tokens":"11","context":"string-tokens"}
EOF

run_check "$LOG_MIXED"
assert_eq "mixed log exits 0" "0" "$rc"
assert_json_expr "mixed log keeps valid codex record" "$OUT_FILE" '.codex.calls == 1 and .codex.est_tokens == 7'
assert_json_expr "mixed log accepts numeric-string tokens" "$OUT_FILE" '.gemini.calls == 1 and .gemini.est_tokens == 11'
assert_contains "mixed log warns on invalid JSON" "skipping invalid JSON object" "$ERR_FILE"
assert_contains "mixed log warns on invalid timestamp" "skipping record with unparseable ts" "$ERR_FILE"
assert_contains "mixed log warns on invalid api" "skipping record with invalid api" "$ERR_FILE"

# Test 6: env overrides for thresholds are honored.
LOG_OVERRIDE="$TMPDIR/override.jsonl"
cat >"$LOG_OVERRIDE" <<EOF
{"ts":"$(iso_hours_ago 1)","api":"claude","type":"wiki_ask","est_tokens":3,"context":"override"}
EOF

run_check "$LOG_OVERRIDE" "USAGE_THRESHOLD_CLAUDE=0"
assert_eq "threshold override exits 10" "10" "$rc"
assert_json_expr "threshold override reports claude" "$OUT_FILE" '.exceeded == ["claude"]'

printf 'PASSED: %s / FAILED: %s\n' "$passed" "$failed"

if [ "$failed" -gt 0 ]; then
  exit 1
fi

exit 0
