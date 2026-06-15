#!/usr/bin/env bash
# Resolve SPM deps and apply kobaamd-specific libghostty-spm patches.
# Run before every swift build / test (E1 agent-status needs readViewportText).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

swift package resolve
bash "$REPO_ROOT/scripts/patch-libghostty-spm.sh"