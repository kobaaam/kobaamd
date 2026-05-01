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

# Sparkle EdDSA 公開鍵を環境変数から注入
# 秘密鍵は Keychain（Sparkle generate_keys が登録）。リポジトリには公開鍵すら直書きしない。
# - debug ビルド: 未設定なら警告のみ（開発を妨げない）
# - release ビルド: 未設定ならエラー終了（安全装置）
PUBLIC_ED_KEY="${KOBAAMD_SU_PUBLIC_ED_KEY:-}"
if [ -n "$PUBLIC_ED_KEY" ]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_ED_KEY" "$PLIST"
  echo "[post-build] SUPublicEDKey injected from KOBAAMD_SU_PUBLIC_ED_KEY (${#PUBLIC_ED_KEY} chars)"
else
  if [ "$CONFIG" = "release" ]; then
    echo "[post-build] ERROR: KOBAAMD_SU_PUBLIC_ED_KEY is not set for release build."
    echo "[post-build]        Sparkle update signature verification will be DISABLED — refusing to ship."
    echo "[post-build]        See docs/wiki/articles/practices/sparkle-release.md for setup."
    exit 1
  else
    echo "[post-build] warning: KOBAAMD_SU_PUBLIC_ED_KEY not set; SUPublicEDKey left empty (debug build OK, but releases require it)"
  fi
fi

# Launch Services に再登録して .md のデフォルトアプリとして認識させる
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null && echo "[post-build] Launch Services registered"

FRAMEWORKS_DIR="$APP/Contents/Frameworks"
SPARKLE_SOURCE=""

echo "[post-build] ensuring Frameworks directory exists → $FRAMEWORKS_DIR"
mkdir -p "$FRAMEWORKS_DIR"

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
  echo "[post-build] replacing bundled Sparkle.framework → $FRAMEWORKS_DIR/Sparkle.framework"
  rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  cp -a "$SPARKLE_SOURCE" "$FRAMEWORKS_DIR/"
else
  echo "[post-build] warning: Sparkle.framework not found for config '$CONFIG'; skipping bundle copy"
fi

echo "[post-build] ensuring LC_RPATH contains @loader_path/../Frameworks"
if ! otool -l "$APP/Contents/MacOS/kobaamd" | grep -q '@loader_path/../Frameworks'; then
  install_name_tool -add_rpath '@loader_path/../Frameworks' "$APP/Contents/MacOS/kobaamd"
  echo "[post-build] LC_RPATH added → @loader_path/../Frameworks"
else
  echo "[post-build] LC_RPATH already present; skipping"
fi

codesign --force --deep --sign - "$APP"
echo "[post-build] codesign applied (ad-hoc) → $APP"

# Touch the app so Dock / Finder picks up the new icon
touch "$APP"
