#!/usr/bin/env bash
# Build kobaamd and run Swift unit tests.
#
# Usage:
#   ./scripts/run-unit-tests.sh                 # run ALL tests (CI default)
#   ./scripts/run-unit-tests.sh --stable-only   # run stable subset only (quick local check)
#   ./scripts/run-unit-tests.sh --filter REGEX  # custom filter
#
# CI runs all tests by default. Use --stable-only for quick local iteration.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Stable subset for quick local checks (--stable-only flag).
STABLE_FILTER='E1Terminal|E1AgentStatus|ColorTheme|EnclosedSymbol|CSVParser|BacklinksScanner|AppState'

FILTER=""
PASSTHROUGH=()

usage() {
  cat <<EOF
Usage: ./scripts/run-unit-tests.sh [--stable-only] [--filter REGEX]

Options:
  --stable-only   Run only the stable test subset (quick local check).
  --filter REGEX  Run tests matching REGEX.

Default (no flags): run ALL tests.
Runs \`swift build\` then \`swift test --no-parallel\`.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --stable-only)
      FILTER="$STABLE_FILTER"
      shift
      ;;
    --filter)
      FILTER="$2"
      shift 2
      ;;
    *)
      PASSTHROUGH+=("$1")
      shift
      ;;
  esac
done

echo "[run-unit-tests] prepare build (resolve + libghostty patch)"
bash "$REPO_ROOT/scripts/prepare-build.sh"

echo "[run-unit-tests] swift build"
swift build

if [[ -n "$FILTER" ]]; then
  CMD=(swift test --enable-swift-testing --no-parallel --filter "$FILTER")
else
  CMD=(swift test --enable-swift-testing --no-parallel)
fi

if ((${#PASSTHROUGH[@]})); then
  CMD+=("${PASSTHROUGH[@]}")
fi

echo "[run-unit-tests] ${CMD[*]}"
"${CMD[@]}"
