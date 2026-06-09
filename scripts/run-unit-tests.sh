#!/usr/bin/env bash
# Run kobaamd Swift unit tests and fail loudly when the runner is a no-op.
#
# Usage:
#   ./scripts/run-unit-tests.sh
#   ./scripts/run-unit-tests.sh --filter E1Terminal
#   ./scripts/run-unit-tests.sh --xunit-output /tmp/kobaamd-xunit.xml
#
# Exit codes:
#   0  tests executed and passed
#   1  tests executed and at least one failed
#   2  build failed
#   3  runner no-op (no tests discovered/executed)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

XUNIT_OUTPUT="${KOBAAMD_XUNIT_OUTPUT:-}"
FILTER_ARGS=()
PASSTHROUGH=()

usage() {
  cat <<'EOF'
Usage: ./scripts/run-unit-tests.sh [--filter REGEX] [--xunit-output PATH]

Runs `swift test` and verifies that tests actually executed.
If SwiftPM only builds and exits 0 without running tests, this script exits 3.

Environment:
  KOBAAMD_XUNIT_OUTPUT  default xUnit report path (optional)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --filter)
      FILTER_ARGS+=(--filter "$2")
      shift 2
      ;;
    --xunit-output)
      XUNIT_OUTPUT="$2"
      shift 2
      ;;
    *)
      PASSTHROUGH+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$XUNIT_OUTPUT" ]]; then
  XUNIT_OUTPUT="$(mktemp -t kobaamd-xunit.XXXXXX.xml)"
  CLEANUP_XUNIT=1
else
  CLEANUP_XUNIT=0
fi

cleanup() {
  if [[ "${CLEANUP_XUNIT:-0}" -eq 1 && -n "${XUNIT_OUTPUT:-}" ]]; then
    rm -f "$XUNIT_OUTPUT"
  fi
}
trap cleanup EXIT

echo "[run-unit-tests] swift test ${FILTER_ARGS[*]:-} (xunit: $XUNIT_OUTPUT)"

set +e
CMD=(swift test --enable-swift-testing --xunit-output "$XUNIT_OUTPUT")
if ((${#FILTER_ARGS[@]})); then
  CMD+=("${FILTER_ARGS[@]}")
fi
if ((${#PASSTHROUGH[@]})); then
  CMD+=("${PASSTHROUGH[@]}")
fi
"${CMD[@]}" 2>&1 | tee /tmp/kobaamd-swift-test.log
TEST_EXIT=${PIPESTATUS[0]}
set -e

if [[ ! -f "$XUNIT_OUTPUT" ]]; then
  echo "[run-unit-tests] ERROR: xUnit report was not created — swift test likely did not run." >&2
  echo "[run-unit-tests] Hint: ensure Package.swift links the swift-testing package product." >&2
  exit 3
fi

TESTS_RUN=$(grep -o 'tests="[0-9]*"' "$XUNIT_OUTPUT" | head -1 | sed -E 's/tests="([0-9]+)"/\1/')
FAILURES=$(grep -o 'failures="[0-9]*"' "$XUNIT_OUTPUT" | head -1 | sed -E 's/failures="([0-9]+)"/\1/')
ERRORS=$(grep -o 'errors="[0-9]*"' "$XUNIT_OUTPUT" | head -1 | sed -E 's/errors="([0-9]+)"/\1/')

TESTS_RUN="${TESTS_RUN:-0}"
FAILURES="${FAILURES:-0}"
ERRORS="${ERRORS:-0}"

if [[ "$TESTS_RUN" -eq 0 ]]; then
  echo "[run-unit-tests] ERROR: 0 tests in xUnit report — runner no-op." >&2
  exit 3
fi

echo "[run-unit-tests] summary: tests=$TESTS_RUN failures=$FAILURES errors=$ERRORS"

if [[ "$TEST_EXIT" -ne 0 || "$FAILURES" -gt 0 || "$ERRORS" -gt 0 ]]; then
  exit 1
fi

exit 0