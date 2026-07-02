#!/usr/bin/env bash
# Dev loop: build → bundle (kobaamd-dev.app) → relaunch dev instance only.
#
# Usage:
#   ./scripts/dev-run.sh          # build once and launch dev app
#   ./scripts/dev-run.sh --watch  # rebuild + relaunch on Sources/ changes
#
# Daily driver (/Applications/kobaamd.app) is left running — dev uses a separate
# bundle ID (com.kobaamd.app.dev) and process name (kobaamd-dev).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP=".build/kobaamd-dev.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
APP_NAME="kobaamd v${VERSION} (Dev)"
EXEC_NAME="kobaamd-dev"
WATCH=false
DEBOUNCE_SEC=1

usage() {
  cat <<'EOF'
Usage: ./scripts/dev-run.sh [--watch] [--debounce SEC]

  (default)   swift build → post-build dev → open kobaamd-dev.app
  --watch     repeat on changes under Sources/, Package.swift, Info.plist
  --debounce  seconds to coalesce rapid saves (default: 1)

Daily driver: keep /Applications/kobaamd.app open for real work.
Dev instance: .build/kobaamd-dev.app (separate settings & tabs).

Requires: swift, fswatch (brew install fswatch) for --watch
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch) WATCH=true; shift ;;
    --debounce) DEBOUNCE_SEC="${2:?--debounce needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

graceful_quit_dev() {
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  for _ in $(seq 1 30); do
    pgrep -x "$EXEC_NAME" >/dev/null || return 0
    sleep 0.1
  done
}

build_and_launch() {
  echo "[dev-run] $(date '+%H:%M:%S') building…"
  graceful_quit_dev
  bash "$REPO_ROOT/scripts/prepare-build.sh"
  swift build
  ./scripts/post-build.sh debug dev
  echo "[dev-run] launching $APP (production kobaamd is untouched)"
  open "$APP"
}

if [[ "$WATCH" == false ]]; then
  build_and_launch
  exit 0
fi

if ! command -v fswatch >/dev/null; then
  echo "[dev-run] ERROR: fswatch not found. Install with: brew install fswatch" >&2
  exit 1
fi

echo "[dev-run] watch mode (debounce ${DEBOUNCE_SEC}s). Ctrl-C to stop."
build_and_launch

watch_paths=(
  "$REPO_ROOT/Sources"
  "$REPO_ROOT/Package.swift"
  "$REPO_ROOT/Info.plist"
)

fswatch -r -l "$DEBOUNCE_SEC" "${watch_paths[@]}" | while read -r _; do
  build_and_launch
done