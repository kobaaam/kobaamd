#!/usr/bin/env bash
# Build kobaamd and run a stable subset of Swift unit tests.
#
# Usage:
#   ./scripts/run-unit-tests.sh
#   ./scripts/run-unit-tests.sh --filter E1Terminal
#
# CI runs the default stable filter. Pass --filter to override locally.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Ghostty 移行後も安定して通るスイートのみ（全 310 件は別途ローカルで）。
DEFAULT_FILTER='E1Terminal|E1AgentStatus|ColorTheme|EnclosedSymbol|CSVParser|BacklinksScanner|AppState'

FILTER="$DEFAULT_FILTER"
PASSTHROUGH=()

usage() {
  cat <<EOF
Usage: ./scripts/run-unit-tests.sh [--filter REGEX]

Runs \`swift build\` then \`swift test --no-parallel\` with a stable filter.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
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

echo "[run-unit-tests] resolve deps"
bash "$REPO_ROOT/scripts/prepare-build.sh"

echo "[run-unit-tests] swift build"
swift build

CMD=(swift test --enable-swift-testing --no-parallel --filter "$FILTER")
if ((${#PASSTHROUGH[@]})); then
  CMD+=("${PASSTHROUGH[@]}")
fi

echo "[run-unit-tests] ${CMD[*]}"
"${CMD[@]}"