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

mkdir -p "$RESOURCES"

# 最新バイナリを .app に反映（最重要）
cp ".build/arm64-apple-macosx/$CONFIG/kobaamd" "$APP/Contents/MacOS/kobaamd"
echo "[post-build] binary updated → $APP/Contents/MacOS/kobaamd"

# Copy app icon
cp Sources/Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"

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

echo "[post-build] icon injected → $RESOURCES/AppIcon.icns"

# Touch the app so Dock / Finder picks up the new icon
touch "$APP"
