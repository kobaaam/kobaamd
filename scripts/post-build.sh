#!/bin/bash
# Post-build: inject AppIcon and brand tokens into the .app bundle
# Usage: ./scripts/post-build.sh [debug|release]

CONFIG=${1:-debug}
APP=".build/kobaamd.app"
RESOURCES="$APP/Contents/Resources"
PLIST="$APP/Contents/Info.plist"

if [ ! -d "$APP" ]; then
  echo "[post-build] .app bundle not found at $APP — run swift build first"
  exit 1
fi

FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"

# 最新バイナリを .app に反映（最重要）
cp ".build/arm64-apple-macosx/$CONFIG/kobaamd" "$APP/Contents/MacOS/kobaamd"
echo "[post-build] binary updated → $APP/Contents/MacOS/kobaamd"

# Sparkle.framework をバンドルにコピー（シンボリックリンク保持）
SPARKLE_SRC=".build/arm64-apple-macosx/$CONFIG/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
  rm -rf "$FRAMEWORKS/Sparkle.framework"
  cp -a "$SPARKLE_SRC" "$FRAMEWORKS/"
  # @loader_path/../Frameworks を rpath に追加（未登録時のみ）
  if ! otool -l "$APP/Contents/MacOS/kobaamd" | grep -q '@loader_path/../Frameworks'; then
    install_name_tool -add_rpath '@loader_path/../Frameworks' "$APP/Contents/MacOS/kobaamd" 2>/dev/null
  fi
  echo "[post-build] Sparkle.framework copied → $FRAMEWORKS/Sparkle.framework"
fi

# Copy app icon
cp Sources/Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
echo "[post-build] icon injected → $RESOURCES/AppIcon.icns"

# Copy resource bundle (JS/CSS assets for WYSIWYG, Mermaid など)
BUNDLE=".build/arm64-apple-macosx/$CONFIG/kobaamd_kobaamd.bundle"
if [ -d "$BUNDLE" ]; then
  cp -r "$BUNDLE" "$RESOURCES/"
  echo "[post-build] resource bundle copied → $RESOURCES/kobaamd_kobaamd.bundle"
fi

# Info.plist をソースの完全版で上書き（CFBundleDocumentTypes + LSHandlerRank 含む）
cp Info.plist "$PLIST"
echo "[post-build] Info.plist updated → $PLIST"

# Launch Services に再登録して .md のデフォルトアプリとして認識させる
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null && echo "[post-build] Launch Services registered"

codesign --force --deep --sign - "$APP"
echo "[post-build] codesign applied (ad-hoc) → $APP"

# Touch the app so Dock / Finder picks up the new icon
touch "$APP"
