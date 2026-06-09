#!/usr/bin/env bash
# 仮説検証用に E1 入力モード別 .app を一括ビルドする。
#
# Usage:
#   ./scripts/build-verify-builds.sh          # 全モードビルド（起動はしない）
#   ./scripts/build-verify-builds.sh --open   # ビルド後 Finder で .build を開く
#   ./scripts/build-verify-builds.sh pty-log  # 1 モードだけビルド
#
# 各 .app のウィンドウタイトルに [verify:MODE] が付く。
# pty-log のログ: ~/Library/Logs/kobaamd/e1-pty-verify.log

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OPEN_FINDER=false
SELECTED_MODES=()

ALL_MODES=(
  pty-log
  drop-space
  term-256color
  kitty-bs
  force-captive
  monitor-only
  keydown-only
  no-kitty-pop
)

usage() {
  cat <<'EOF'
Usage: ./scripts/build-verify-builds.sh [--open] [MODE ...]

Modes (仮説):
  pty-log         H1/H3 診断 — PTY バイト列 + 経路ログ
  drop-space      H1 — Captive 中 0x20 PTY 送信を遮断
  term-256color   H2 — TERM=xterm-256color
  kitty-bs        H2 — Backspace を \e[127u で送信
  force-captive   H4 — 常時 Captive
  monitor-only    H3 — key monitor のみ
  keydown-only    H3 — keyDown のみ
  no-kitty-pop    H2 対照 — kitty pop 無効

Output: .build/kobaamd-verify-<MODE>.app  (並行インストール可)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) OPEN_FINDER=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ " ${ALL_MODES[*]} " == *" $1 "* ]]; then
        SELECTED_MODES+=("$1")
      else
        echo "Unknown mode: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ ${#SELECTED_MODES[@]} -eq 0 ]]; then
  SELECTED_MODES=("${ALL_MODES[@]}")
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD_BINARY=".build/arm64-apple-macosx/debug/kobaamd"
ENTITLEMENTS="Sources/Resources/kobaamd.entitlements"

echo "[verify-build] version=$VERSION modes=${SELECTED_MODES[*]}"
swift build

if [[ ! -f "$BUILD_BINARY" ]]; then
  echo "[verify-build] binary missing at $BUILD_BINARY" >&2
  exit 1
fi

# ベース dev バンドルを 1 回だけ用意
./scripts/post-build.sh debug dev

scaffold_verify_app() {
  local mode="$1"
  local app=".build/kobaamd-verify-${mode}.app"
  local exec_name="kobaamd-verify-${mode}"
  local bundle_id="com.kobaamd.app.verify.${mode}"
  local display_name="kobaamd v${VERSION} [${mode}]"

  rm -rf "$app"
  cp -a ".build/kobaamd-dev.app" "$app"

  local plist="$app/Contents/Info.plist"
  local macos="$app/Contents/MacOS"
  local binary_dst="$macos/$exec_name"

  cp "$BUILD_BINARY" "$binary_dst"
  chmod +x "$binary_dst"
  rm -f "$macos/kobaamd-dev" "$macos/kobaamd" 2>/dev/null || true

  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $exec_name" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display_name" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $exec_name" "$plist"
  /usr/libexec/PlistBuddy -c "Delete :KOBAAMD_E1_VERIFY" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :KOBAAMD_E1_VERIFY string $mode" "$plist"

  if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --deep --sign - --options runtime --entitlements "$ENTITLEMENTS" "$app" >/dev/null
  else
    codesign --force --deep --sign - --options runtime "$app" >/dev/null
  fi

  touch "$app"
  echo "[verify-build] $app ← $mode"
}

for mode in "${SELECTED_MODES[@]}"; do
  scaffold_verify_app "$mode"
done

cat <<EOF

[verify-build] done (${#SELECTED_MODES[@]} apps)

試す順序（推奨）:
  1. pty-log      → ログで 0x20 が出るか確認
     tail -f ~/Library/Logs/kobaamd/e1-pty-verify.log
  2. drop-space   → 空白が消えるなら H1 確定
  3. term-256color / kitty-bs → H2 切り分け
  4. monitor-only / keydown-only → H3 経路切り分け
  5. force-captive → H4
  6. no-kitty-pop  → pop の効果

起動例:
  open .build/kobaamd-verify-pty-log.app

EOF

if [[ "$OPEN_FINDER" == true ]]; then
  open ".build"
fi