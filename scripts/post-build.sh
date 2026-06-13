#!/bin/bash
# Post-build: inject AppIcon and brand tokens into the .app bundle
# Usage:
#   ./scripts/post-build.sh [debug|release]           # → .build/kobaamd.app
#   ./scripts/post-build.sh [debug|release] dev       # → .build/kobaamd-dev.app
#
# dev プロファイルは別 Bundle ID / 別プロセス名 (kobaamd-dev) なので、
# /Applications/kobaamd.app を日常利用しながら開発ビルドを回せる。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG=${1:-debug}
PROFILE=${2:-prod}

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

case "$PROFILE" in
  dev)
    APP=".build/kobaamd-dev.app"
    EXEC_NAME="kobaamd-dev"
    BUNDLE_ID="com.kobaamd.app.dev"
    DISPLAY_NAME="kobaamd v${VERSION} (Dev)"
    REGISTER_LS=false
    ;;
  prod|*)
    APP=".build/kobaamd.app"
    EXEC_NAME="kobaamd"
    BUNDLE_ID="com.kobaamd.app"
    DISPLAY_NAME="kobaamd v${VERSION}"
    REGISTER_LS=true
    ;;
esac

MACOS_DIR="$APP/Contents/MacOS"
BINARY_DST="$MACOS_DIR/$EXEC_NAME"
RESOURCES="$APP/Contents/Resources"
PLIST="$APP/Contents/Info.plist"
FRAMEWORKS="$APP/Contents/Frameworks"
BUILD_BINARY=".build/arm64-apple-macosx/$CONFIG/kobaamd"
BUNDLE_ABS="$REPO_ROOT/$APP"

ensure_app_bundle() {
  if [ -d "$APP" ]; then
    return
  fi
  if [ "$PROFILE" = "dev" ] && [ -d ".build/kobaamd.app" ]; then
    cp -a ".build/kobaamd.app" "$APP"
    rm -f "$MACOS_DIR/kobaamd" "$MACOS_DIR/kobaamd-dev" 2>/dev/null || true
    echo "[post-build] scaffolded $APP from kobaamd.app"
    return
  fi
  mkdir -p "$MACOS_DIR" "$RESOURCES" "$FRAMEWORKS"
  echo "[post-build] created empty bundle skeleton → $APP"
}

# Hardened Runtime 下での binary 上書き SIGKILL 回避 (KMD-151)
# prod: この .app から起動したプロセスだけ停止（/Applications の本番は触らない）
# dev:  プロセス名 kobaamd-dev のみ停止（本番 kobaamd は無関係）
stop_running_target() {
  if [ "$PROFILE" = "dev" ]; then
    pkill -x "$EXEC_NAME" 2>/dev/null || true
    return
  fi

  local target_binary="$BUNDLE_ABS/Contents/MacOS/$EXEC_NAME"
  local pid path
  for pid in $(pgrep -x "$EXEC_NAME" 2>/dev/null); do
    path=$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
    if [ "$path" = "$target_binary" ]; then
      echo "[post-build] stopping $EXEC_NAME (pid $pid) from $APP"
      kill "$pid" 2>/dev/null || true
    fi
  done
}

ensure_app_bundle
stop_running_target

if [ ! -f "$BUILD_BINARY" ]; then
  echo "[post-build] binary not found at $BUILD_BINARY"
  echo "[post-build] run: ./scripts/prepare-build.sh && swift build -c $CONFIG"
  exit 1
fi

mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"

cp "$BUILD_BINARY" "$BINARY_DST"
chmod +x "$BINARY_DST"
echo "[post-build] binary updated → $BINARY_DST"

cp Sources/Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
echo "[post-build] icon injected → $RESOURCES/AppIcon.icns"

BUNDLE=".build/arm64-apple-macosx/$CONFIG/kobaamd_kobaamd.bundle"
if [ -d "$BUNDLE" ]; then
  cp -r "$BUNDLE" "$RESOURCES/"
  echo "[post-build] resource bundle copied → $RESOURCES/kobaamd_kobaamd.bundle"
fi

cp Info.plist "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXEC_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $EXEC_NAME" "$PLIST"
if [ "$PROFILE" = "dev" ]; then
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST" 2>/dev/null || true
fi
echo "[post-build] Info.plist updated → $PLIST ($BUNDLE_ID)"

/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST" 2>/dev/null || true
echo "[post-build] Sparkle keys removed from Info.plist (auto-update disabled)"

if [ "$REGISTER_LS" = true ]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null && echo "[post-build] Launch Services registered"
else
  echo "[post-build] skipping Launch Services registration (dev profile)"
fi

ENTITLEMENTS="Sources/Resources/kobaamd.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
  codesign --force --deep --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP"
  echo "[post-build] codesign applied (Hardened Runtime, ad-hoc, entitlements=$ENTITLEMENTS) → $APP"
else
  codesign --force --deep --sign - --options runtime "$APP"
  echo "[post-build] codesign applied (Hardened Runtime, ad-hoc, no entitlements) → $APP"
fi
codesign --display --verbose=4 "$APP" 2>&1 | grep -E '^(Identifier|Format|Signature|TeamIdentifier|flags|CodeDirectory)' | sed 's/^/[post-build]   /'

touch "$APP"