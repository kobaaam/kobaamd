#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="$ROOT/ThirdParty/libghostty-spm-patches"
CHECKOUT="$ROOT/.build/checkouts/libghostty-spm/Sources/GhosttyTerminal"

if [[ ! -d "$CHECKOUT" ]]; then
  echo "patch-libghostty-spm: checkout missing (run swift package resolve first)" >&2
  exit 0
fi

cp "$PATCH_DIR/TerminalSurface+ViewportRead.swift" \
  "$CHECKOUT/Surface/TerminalSurface+ViewportRead.swift"
cp "$PATCH_DIR/TerminalSurface+ScreenRead.swift" \
  "$CHECKOUT/Surface/TerminalSurface+ScreenRead.swift"
cp "$PATCH_DIR/AppTerminalView+ViewportRead.swift" \
  "$CHECKOUT/Platform/AppKit/AppTerminalView+ViewportRead.swift"
cp "$PATCH_DIR/AppTerminalView+ScreenRead.swift" \
  "$CHECKOUT/Platform/AppKit/AppTerminalView+ScreenRead.swift"