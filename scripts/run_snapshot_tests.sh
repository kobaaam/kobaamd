#!/bin/bash
# Snapshot test runner for kobaamd
# Builds and runs the snapshot-runner SPM executable target.
# Bypasses swift test (broken on CommandLineTools) by using a standalone executable.
#
# Usage:
#   ./scripts/run_snapshot_tests.sh --record  # Generate reference images
#   ./scripts/run_snapshot_tests.sh            # Compare against references

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

SNAPSHOT_DIR="Tests/kobaamdTests/__Snapshots__"
FAILURE_DIR="$SNAPSHOT_DIR/_failures"
RUNNER_BIN=".build/arm64-apple-macosx/debug/snapshot-runner"

RECORD_MODE=false
if [[ "${1:-}" == "--record" ]]; then
    RECORD_MODE=true
fi

# Step 1: Build snapshot-runner target (also builds kobaamdLib dependency)
echo "🔨 Building snapshot-runner..."
swift build --target snapshot-runner 2>&1 | tail -3

# Step 2: Run
echo "🧪 Running snapshot tests..."
EXIT_CODE=0
if [[ "$RECORD_MODE" == "true" ]]; then
    SNAPSHOT_RECORD=true "$RUNNER_BIN" || EXIT_CODE=$?
else
    "$RUNNER_BIN" || EXIT_CODE=$?
fi

# Step 3: Report
echo ""
if [[ -d "$SNAPSHOT_DIR" ]]; then
    REF_COUNT=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name "*.png" | wc -l | tr -d ' ')
    FAIL_COUNT=$(find "$FAILURE_DIR" -name "*_actual.png" 2>/dev/null | wc -l | tr -d ' ' || true)
    echo "📊 References: $REF_COUNT, Failures: $FAIL_COUNT"
fi

exit $EXIT_CODE
