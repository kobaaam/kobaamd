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

case "$PROFILE" in
  dev)
    APP=".build/kobaamd-dev.app"
    EXEC_NAME="kobaamd-dev"
    BUNDLE_ID="com.kobaamd.app.dev"
    DISPLAY_NAME="kobaamd (Dev)"
    REGISTER_LS=false
    ;;
  prod|*)
    APP=".build/kobaamd.app"
    EXEC_NAME="kobaamd"
    BUNDLE_ID="com.kobaamd.app"
    DISPLAY_NAME="kobaamd"
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
  echo "[post-build] binary not found at $BUILD_BINARY — run swift build first"
  exit 1
fi

mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"

cp "$BUILD_BINARY" "$BINARY_DST"
chmod +x "$BINARY_DST"
echo "[post-build] binary updated → $BINARY_DST"

SPARKLE_SRC=".build/arm64-apple-macosx/$CONFIG/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
  rm -rf "$FRAMEWORKS/Sparkle.framework"
  cp -a "$SPARKLE_SRC" "$FRAMEWORKS/"
  if ! otool -l "$BINARY_DST" | grep -q '@loader_path/../Frameworks'; then
    install_name_tool -add_rpath '@loader_path/../Frameworks' "$BINARY_DST" 2>/dev/null
  fi
  echo "[post-build] Sparkle.framework copied → $FRAMEWORKS/Sparkle.framework"
fi

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

PUBLIC_ED_KEY="${KOBAAMD_SU_PUBLIC_ED_KEY:-}"
if [ -n "$PUBLIC_ED_KEY" ]; then
  if [[ ! "$PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "[post-build] ERROR: KOBAAMD_SU_PUBLIC_ED_KEY does not match Ed25519 Base64 format (43 base64 chars + '=')."
    echo "[post-build]        Received ${#PUBLIC_ED_KEY} chars: '${PUBLIC_ED_KEY:0:20}...'"
    echo "[post-build]        Refusing to inject invalid key. Re-run generate_keys to obtain the correct public key."
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey \"$PUBLIC_ED_KEY\"" "$PLIST"
  WRITTEN_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" 2>/dev/null || echo "")
  if [ "$WRITTEN_KEY" != "$PUBLIC_ED_KEY" ]; then
    echo "[post-build] ERROR: SUPublicEDKey write verification failed."
    echo "[post-build]        Expected: '$PUBLIC_ED_KEY'"
    echo "[post-build]        Got:      '$WRITTEN_KEY'"
    exit 1
  fi
  echo "[post-build] SUPublicEDKey injected and verified from KOBAAMD_SU_PUBLIC_ED_KEY (${#PUBLIC_ED_KEY} chars)"
else
  if [ "$CONFIG" = "release" ] && [ "$PROFILE" != "dev" ]; then
    echo "[post-build] ERROR: KOBAAMD_SU_PUBLIC_ED_KEY is not set for release build."
    echo "[post-build]        Sparkle update signature verification will be DISABLED — refusing to ship."
    echo "[post-build]        See docs/wiki/articles/practices/sparkle-release.md for setup."
    exit 1
  else
    echo "[post-build] warning: KOBAAMD_SU_PUBLIC_ED_KEY not set; SUPublicEDKey left empty (debug/dev build OK)"
  fi
fi

if [ "$REGISTER_LS" = true ]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null && echo "[post-build] Launch Services registered"
else
  echo "[post-build] skipping Launch Services registration (dev profile)"
fi

SPARKLE_SOURCE=""
for candidate in \
  ".build/arm64-apple-macosx/$CONFIG/Sparkle.framework" \
  ".build/arm64-apple-macosx/$CONFIG/PackageFrameworks/Sparkle.framework" \
  ".build/$CONFIG/Sparkle.framework"
do
  if [ -d "$candidate" ]; then
    SPARKLE_SOURCE="$candidate"
    break
  fi
done

if [ -n "$SPARKLE_SOURCE" ]; then
  echo "[post-build] Sparkle.framework found → $SPARKLE_SOURCE"
  rm -rf "$FRAMEWORKS/Sparkle.framework"
  cp -a "$SPARKLE_SOURCE" "$FRAMEWORKS/"
fi

if ! otool -l "$BINARY_DST" | grep -q '@loader_path/../Frameworks'; then
  install_name_tool -add_rpath '@loader_path/../Frameworks' "$BINARY_DST"
  echo "[post-build] LC_RPATH added → @loader_path/../Frameworks"
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