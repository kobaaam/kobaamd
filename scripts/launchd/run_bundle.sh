#!/usr/bin/env bash
# kobaamd 自律パイプラインのバンドル実行ラッパー
# 使い方: run_bundle.sh <bundle_name>
# 例:    run_bundle.sh kobaamd_pipeline_active
#
# 動作:
#   1. claude -p "/<bundle_name>" を実行
#   2. 経過時間と結果を計測
#   3. macOS 通知センターに結果を表示
#   4. 標準出力/標準エラーは .logs/<bundle_name>.log に追記
#
# 環境変数:
#   KOBAAMD_NOTIFY_LEVEL = all | error | none
#     - all   (default): 成功・失敗とも通知
#     - error          : 失敗時のみ通知
#     - none           : 通知なし
#   KOBAAMD_NOTIFY_SOUND = "" or sound name
#     - 空文字 (default): 無音
#     - "Glass" "Ping" 等の macOS システムサウンド名
#   KOBAAMD_SLACK_WEBHOOK_URL
#     - 設定すると Slack にも投稿（オプション）

set -uo pipefail

BUNDLE="${1:?Usage: $0 <bundle_name>}"
NOTIFY_LEVEL="${KOBAAMD_NOTIFY_LEVEL:-all}"
NOTIFY_SOUND="${KOBAAMD_NOTIFY_SOUND:-}"
SLACK_URL="${KOBAAMD_SLACK_WEBHOOK_URL:-}"

# このスクリプトの 2 階層上が kobaamd ルート
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOBAAMD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$KOBAAMD_DIR/.logs"
LOG="$LOG_DIR/${BUNDLE}.log"

mkdir -p "$LOG_DIR"
cd "$KOBAAMD_DIR"

# launchd の最小環境で claude / codex 等が PATH に無い対策
# bash から zshrc は読めないため、zsh -c で PATH を取得する
eval "$(zsh -lc 'echo "export PATH=\"$PATH\""' 2>/dev/null)" || true

# ---- 実行 ----
{
  echo ""
  echo "==== $(date '+%Y-%m-%d %H:%M:%S') start: /$BUNDLE ===="
} >> "$LOG"

START=$(date +%s)

# tee でリアルタイムにログ書き出し + 変数キャプチャ（レート制限検出用）
OUTPUT_FILE="$LOG_DIR/.${BUNDLE}.lastrun"
claude -p "/$BUNDLE" 2>&1 | tee "$OUTPUT_FILE" >> "$LOG"
EXIT_CODE=${PIPESTATUS[0]}
ELAPSED=$(( $(date +%s) - START ))

# ---- レート制限検出 ----
if grep -qiE "hit your limit|rate.?limit|quota exceeded" "$OUTPUT_FILE" 2>/dev/null; then
  {
    echo "==== $(date '+%Y-%m-%d %H:%M:%S') RATE_LIMITED: /$BUNDLE (${ELAPSED}s) ===="
    echo "Claude API レート制限に到達。次のリセットまで待機が必要です。"
  } >> "$LOG"
  osascript -e 'display notification "Claude API レート制限到達。次のリセットまで待機。" with title "⚠ kobaamd pipeline blocked"' 2>/dev/null
  rm -f "$OUTPUT_FILE"
  exit 2
fi

rm -f "$OUTPUT_FILE"

{
  echo "==== $(date '+%Y-%m-%d %H:%M:%S') end: /$BUNDLE (exit=$EXIT_CODE, ${ELAPSED}s) ===="
} >> "$LOG"

# ---- 通知本文の組み立て ----
LAST_LINES=$(tail -3 "$LOG" | tr '\n' ' ' | sed 's/"/\\"/g; s/\\/\\\\/g' | head -c 180)
SHORT="${BUNDLE#kobaamd_pipeline_}"
if [ "$SHORT" = "$BUNDLE" ]; then SHORT="$BUNDLE"; fi  # pipeline 系以外もそのまま

if [ "$EXIT_CODE" -eq 0 ]; then
  TITLE="✓ kobaamd $SHORT 完了"
  STATUS="success"
else
  TITLE="✗ kobaamd $SHORT 失敗 (exit $EXIT_CODE)"
  STATUS="failed"
fi
SUBTITLE="${ELAPSED}秒"

# ---- macOS 通知 ----
should_notify_mac() {
  case "$NOTIFY_LEVEL" in
    all)   return 0 ;;
    error) [ "$EXIT_CODE" -ne 0 ] && return 0 || return 1 ;;
    none)  return 1 ;;
    *)     return 0 ;;
  esac
}

if should_notify_mac; then
  if [ -n "$NOTIFY_SOUND" ]; then
    osascript -e "display notification \"$LAST_LINES\" with title \"$TITLE\" subtitle \"$SUBTITLE\" sound name \"$NOTIFY_SOUND\""
  else
    osascript -e "display notification \"$LAST_LINES\" with title \"$TITLE\" subtitle \"$SUBTITLE\""
  fi
fi

# ---- Slack 通知（オプション） ----
if [ -n "$SLACK_URL" ] && should_notify_mac; then
  PAYLOAD=$(cat <<JSON
{
  "text": "${TITLE}",
  "blocks": [
    {"type":"section","text":{"type":"mrkdwn","text":"*${TITLE}*\n${SUBTITLE} / status: ${STATUS}\n\`\`\`${LAST_LINES}\`\`\`"}}
  ]
}
JSON
)
  curl -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$SLACK_URL" >/dev/null 2>&1 || true
fi

exit $EXIT_CODE
