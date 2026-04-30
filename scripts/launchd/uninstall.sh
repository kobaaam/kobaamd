#!/usr/bin/env bash
# kobaamd 自律パイプライン launchd 完全撤去
set -euo pipefail

LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
PLISTS=(
  "com.kobaamd.pipeline_active.plist"
  "com.kobaamd.pipeline_daily.plist"
  "com.kobaamd.pipeline_weekly.plist"
)

for plist in "${PLISTS[@]}"; do
  dst="$LAUNCHAGENTS_DIR/$plist"
  if [[ -f "$dst" ]]; then
    label="${plist%.plist}"
    echo "==> bootout: $label"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm "$dst"
    echo "==> removed: $dst"
  fi
done

echo ""
echo "✓ アンインストール完了"
echo ""
launchctl list | grep kobaamd && echo "WARN: 残存ジョブあり" || echo "kobaamd ジョブはすべて停止しました"
