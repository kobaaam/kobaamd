#!/usr/bin/env bash
# kobaamd 自律パイプラインのバンドル実行ラッパー
# 使い方: run_bundle.sh <bundle_name>
# 例:    run_bundle.sh kobaamd_pipeline_active
#
# 動作:
#   1. scripts/codex/autopilot.sh <bundle_name> を実行
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
#   KOBAAMD_USAGE_GUARD = 1 | 0
#     - 1 (default): Codex 起動前に soft usage threshold を確認
#   KOBAAMD_USAGE_SOFT_THRESHOLD_CODEX / _GEMINI / _CLAUDE
#     - 既定: Codex 35 / Gemini 20 / Claude 80（5h window）
#   KOBAAMD_USAGE_WINDOW_HOURS
#     - 既定: 5

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

LOCK_DIR="$LOG_DIR/.${BUNDLE}.lock"
LOCK_ACQUIRED=0

release_lock() {
  if [ "$LOCK_ACQUIRED" -eq 1 ]; then
    rm -f "$LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

send_macos_notification() {
  local body="$1"
  local title="$2"
  local subtitle="${3:-}"
  local sound="${4:-}"

  if [ -n "$sound" ]; then
    osascript - "$body" "$title" "$subtitle" "$sound" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv) sound name (item 4 of argv)
end run
APPLESCRIPT
  else
    osascript - "$body" "$title" "$subtitle" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)
end run
APPLESCRIPT
  fi
}

acquire_lock() {
  local existing_pid=""

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    LOCK_ACQUIRED=1
    trap release_lock EXIT
    return 0
  fi

  existing_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    {
      echo ""
      echo "==== $(date '+%Y-%m-%d %H:%M:%S') skip: /$BUNDLE (already running pid=$existing_pid) ===="
    } >> "$LOG"
    exit 0
  fi

  rm -f "$LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    LOCK_ACQUIRED=1
    trap release_lock EXIT
    return 0
  fi

  {
    echo ""
    echo "==== $(date '+%Y-%m-%d %H:%M:%S') skip: /$BUNDLE (lock unavailable) ===="
  } >> "$LOG"
  exit 0
}

acquire_lock

# launchd の最小環境で codex / gh 等が PATH に無い対策
# bash から zshrc は読めないため、zsh -c で PATH を取得する
# printf %q（autopilot.sh と同方式）でシェル特殊文字を安全にクオートする。
eval "$(zsh -lc 'printf "export PATH=%q\n" "$PATH"' 2>/dev/null)"

PREFLIGHT_OUT=""
PREFLIGHT_EXIT=0

# ---- pre-flight check (KMD-194) ----
# pipeline_active のみ、対象 issue ゼロなら Codex 起動を skip して
# メインセッションのトークン消費を 0 にする。
# preflight 自体が失敗（exit 2）したら fail-open で通常起動する。
if [ "$BUNDLE" = "kobaamd_pipeline_active" ] && [ -x "$SCRIPT_DIR/preflight_check.sh" ]; then
  PREFLIGHT_OUT=$("$SCRIPT_DIR/preflight_check.sh" 2>&1)
  PREFLIGHT_EXIT=$?
  {
    echo ""
    echo "==== $(date '+%Y-%m-%d %H:%M:%S') preflight: /$BUNDLE (exit=$PREFLIGHT_EXIT) ===="
    echo "$PREFLIGHT_OUT"
  } >> "$LOG"
  if [ "$PREFLIGHT_EXIT" -eq 1 ]; then
    {
      echo "==== $(date '+%Y-%m-%d %H:%M:%S') skip: /$BUNDLE (preflight skip, no codex session started) ===="
    } >> "$LOG"
    # macOS 通知は出さない（30 分毎の skip 通知は noise なので all モードでも抑止）
    exit 0
  fi
fi

# ---- usage soft guard ----
# The legacy in-agent usage check happens after Codex has already consumed a
# session. This guard runs before model startup. When usage is high, keep only
# cheap/high-value active work (already-Reviewed merge and Human-in-Review
# handling) and defer new implementation/review/daily/weekly work.
if [ "${KOBAAMD_USAGE_GUARD:-1}" = "1" ] && [ -x "$KOBAAMD_DIR/scripts/usage/check.sh" ]; then
  USAGE_OUT=$(
    USAGE_THRESHOLD_CLAUDE="${KOBAAMD_USAGE_SOFT_THRESHOLD_CLAUDE:-80}" \
    USAGE_THRESHOLD_CODEX="${KOBAAMD_USAGE_SOFT_THRESHOLD_CODEX:-35}" \
    USAGE_THRESHOLD_GEMINI="${KOBAAMD_USAGE_SOFT_THRESHOLD_GEMINI:-20}" \
    "$KOBAAMD_DIR/scripts/usage/check.sh" --window-hours "${KOBAAMD_USAGE_WINDOW_HOURS:-5}" --json 2>&1
  )
  USAGE_EXIT=$?
  {
    echo ""
    echo "==== $(date '+%Y-%m-%d %H:%M:%S') usage-guard: /$BUNDLE (exit=$USAGE_EXIT) ===="
    echo "$USAGE_OUT"
  } >> "$LOG"

  if [ "$USAGE_EXIT" -eq 10 ]; then
    if [ "$BUNDLE" = "kobaamd_pipeline_active" ] \
       && echo "$PREFLIGHT_OUT" | grep -qE 'PREFLIGHT_PROCEED: (reviewed=|human_in_review=)'; then
      {
        echo "==== $(date '+%Y-%m-%d %H:%M:%S') usage-guard proceed: /$BUNDLE (critical active work only) ===="
      } >> "$LOG"
    else
      EXCEEDED=$(echo "$USAGE_OUT" | jq -r '.exceeded | join(", ")' 2>/dev/null || echo "unknown")
      {
        echo "==== $(date '+%Y-%m-%d %H:%M:%S') skip: /$BUNDLE (usage soft threshold exceeded: $EXCEEDED, no codex session started) ===="
      } >> "$LOG"
      exit 0
    fi
  elif [ "$USAGE_EXIT" -ne 0 ]; then
    {
      echo "==== $(date '+%Y-%m-%d %H:%M:%S') usage-guard warn: /$BUNDLE (check failed, fail-open) ===="
    } >> "$LOG"
  fi
fi

# ---- 実行 ----
{
  echo ""
  echo "==== $(date '+%Y-%m-%d %H:%M:%S') start: /$BUNDLE ===="
} >> "$LOG"

START=$(date +%s)

# tee でリアルタイムにログ書き出し + 変数キャプチャ（レート制限検出用）
OUTPUT_FILE="$LOG_DIR/.${BUNDLE}.lastrun"
CODEX_RUN_LOGGED_BY_BUNDLE=1 "$KOBAAMD_DIR/scripts/codex/autopilot.sh" "$BUNDLE" 2>&1 | tee "$OUTPUT_FILE" >> "$LOG"
EXIT_CODE=${PIPESTATUS[0]}
ELAPSED=$(( $(date +%s) - START ))

if [ "${CODEX_RUN_DRY_RUN:-0}" != "1" ]; then
  TOKENS_USED=$(
    awk '
      /^tokens used$/ {
        if (getline value) {
          gsub(/,/, "", value)
          if (value ~ /^[0-9]+$/) print value
        }
      }
    ' "$OUTPUT_FILE" | tail -1
  )
  if [[ ! "$TOKENS_USED" =~ ^[0-9]+$ ]]; then
    TOKENS_USED=0
  fi
  "$KOBAAMD_DIR/scripts/usage/log.sh" codex "$BUNDLE" "$TOKENS_USED" "$BUNDLE" || true
fi

# ---- レート制限検出 ----
# Match concrete Codex/OpenAI error lines only. The launchd prompt itself
# contains policy text such as "quota/rate-limit blocked reports", so a broad
# `rate.?limit` match turns successful runs into false RATE_LIMITED failures.
RATE_LIMIT_PATTERN="ERROR:.*(hit your usage limit|usage limit|rate.?limit|quota|insufficient_quota)|You've hit your usage limit|429 Too Many Requests|quota exceeded"
if grep -qiE "$RATE_LIMIT_PATTERN" "$OUTPUT_FILE" 2>/dev/null; then
  {
    echo "==== $(date '+%Y-%m-%d %H:%M:%S') RATE_LIMITED: /$BUNDLE (${ELAPSED}s) ===="
    echo "Codex API レート制限に到達。次のリセットまで待機が必要です。"
  } >> "$LOG"
  send_macos_notification "Codex API レート制限到達。次のリセットまで待機。" "⚠ kobaamd pipeline blocked"
  rm -f "$OUTPUT_FILE"
  exit 2
fi

rm -f "$OUTPUT_FILE"

{
  echo "==== $(date '+%Y-%m-%d %H:%M:%S') end: /$BUNDLE (exit=$EXIT_CODE, ${ELAPSED}s) ===="
} >> "$LOG"

# ---- 通知本文の組み立て ----
LAST_LINES=$(tail -3 "$LOG" | tr '\n' ' ' | head -c 180)
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
  send_macos_notification "$LAST_LINES" "$TITLE" "$SUBTITLE" "$NOTIFY_SOUND"
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
