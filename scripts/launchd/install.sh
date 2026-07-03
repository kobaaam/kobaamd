#!/usr/bin/env bash
# kobaamd 自律パイプライン launchd インストーラ
# 使い方: cd ~/Documents/Claude/Projects/dev/kobaamd && ./scripts/launchd/install.sh
# 冪等: 既に load 済みなら一旦 unload してから再 load
set -euo pipefail

# このスクリプトの 2 階層上が kobaamd ルート
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOBAAMD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"

PLISTS=(
  "com.kobaamd.pipeline_active.plist"
  "com.kobaamd.pipeline_daily.plist"
  "com.kobaamd.pipeline_weekly.plist"
)

echo "==> kobaamd dir: $KOBAAMD_DIR"
echo "==> launch agents: $LAUNCHAGENTS_DIR"
mkdir -p "$LAUNCHAGENTS_DIR"
mkdir -p "$KOBAAMD_DIR/.logs"

# Codex CLI のパス確認
if ! command -v codex >/dev/null 2>&1; then
  echo "WARN: 'codex' コマンドが PATH に見つかりません。"
  echo "      ~/.zshrc で PATH が通っているか確認してください。"
  echo "      run_bundle.sh は zsh -lc で PATH を補完します。"
fi

for plist in "${PLISTS[@]}"; do
  src="$SCRIPT_DIR/$plist"
  dst="$LAUNCHAGENTS_DIR/$plist"
  label="${plist%.plist}"

  if [[ ! -f "$src" ]]; then
    echo "ERROR: $src が見つかりません"
    exit 1
  fi

  UID_NUM=$(id -u)
  DOMAIN="gui/$UID_NUM"

  # 既に load されていたら bootout
  if launchctl list 2>/dev/null | grep -q "${label}"; then
    echo "==> bootout existing: $label"
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
  fi

  # __KOBAAMD_DIR__ プレースホルダを実パスに置換してコピー
  sed "s|__KOBAAMD_DIR__|$KOBAAMD_DIR|g" "$src" > "$dst"

  echo "==> bootstrap: $label"
  launchctl bootstrap "$DOMAIN" "$dst"
done

echo ""
echo "✓ インストール完了"
echo ""
echo "確認:"
launchctl list | grep kobaamd || echo "  (kobaamd ジョブが見つかりません — 上のエラー出力を確認)"
echo ""
echo "即時手動実行（タイマー待たずに動作確認）:"
echo "  launchctl start com.kobaamd.pipeline_active"
echo ""
echo "ログ tail:"
echo "  tail -f $KOBAAMD_DIR/.logs/pipeline_active.log"
echo ""
echo "停止:"
echo "  launchctl unload $LAUNCHAGENTS_DIR/com.kobaamd.pipeline_active.plist"
