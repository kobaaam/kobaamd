#!/usr/bin/env bash
# run.sh — Codex CLI wrapper with quota / rate-limit detection.
#
# 3 subagent (kobaamd_implement_code / kobaamd_fix_pr_comments /
# kobaamd_rework_issue) で共通利用する `codex exec` の前段スクリプト。
#
# 役割:
#   1. stdin 経由で codex exec を実行（stdout はそのまま親に流す）
#   2. exit code が 0 でない、もしくは stderr に 429 / rate_limit /
#      quota / usage limit のパターンが出たら BLOCKED と判定
#   3. BLOCKED の場合は Linear に `[BLOCKED] Codex quota` チケットを
#      起票（既存があれば skip）、exit code 42 で抜ける
#   4. それ以外は codex の exit code をそのまま伝播
#
# 使い方:
#   cat << 'EOF' | ./scripts/codex/run.sh
#   <prompt>
#   EOF
#
# Env:
#   LINEAR_API_KEY  required（BLOCKED 起票時のみ）
#   CODEX_RUN_TEAM  default: KMD（BLOCKED 起票先 team key）
#   CODEX_RUN_CONTEXT
#                   optional usage log context（KMD-XX など）
#   CODEX_RUN_DRY_RUN=1
#                   skip codex 実行 + Linear 起票のスキップ判定だけ実施
#   CODEX_EXEC_MODEL
#                   optional model passed to `codex exec -m`
#   CODEX_EXEC_SANDBOX
#                   sandbox passed to `codex exec -s` (default: workspace-write)
#   CODEX_EXEC_CD
#                   working directory passed to `codex exec -C` (default: repo root)
#
# Exit codes:
#   0    成功（codex exec が 0、stderr に quota パターンなし）
#   42   BLOCKED 検出（quota / rate_limit / 429 / usage limit）
#   その他 codex exec の exit code をそのまま伝播

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LQ="${REPO_ROOT}/scripts/linear/lq.sh"
LOG_DIR="${REPO_ROOT}/.logs"
RUN_LOG="${LOG_DIR}/codex_runs.jsonl"
TEAM="${CODEX_RUN_TEAM:-KMD}"
DRY_RUN="${CODEX_RUN_DRY_RUN:-0}"

# BLOCKED 検出パターン（拡張正規表現、grep -E -i）
# - 429        : HTTP 429 Too Many Requests
# - rate.?limit: rate limit / rate-limit / ratelimit
# - quota      : quota exceeded / quota_exceeded
# - usage.?limit: usage limit / usage_limit
# - insufficient_quota: OpenAI 公式エラーコード
QUOTA_PATTERN='(^|[^0-9])429([^0-9]|$)|rate.?limit|quota|usage.?limit|insufficient_quota'

mkdir -p "$LOG_DIR"

err() { echo "codex/run.sh: $*" >&2; }
log_run() {
  local exit_code="$1" matched="$2" stderr_snippet="$3"
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --argjson code "$exit_code" \
         --arg matched "$matched" \
         --arg snippet "$stderr_snippet" \
         '{ts:$ts, exit_code:$code, blocked:$matched, stderr_snippet:$snippet}' \
    >> "$RUN_LOG"
}

# 既存の [BLOCKED] Codex quota issue を検索する。
# 戻り値: 0 = 既存あり / 1 = 既存なし / 2 = 検索失敗
existing_blocked_issue() {
  command -v jq >/dev/null || return 2
  [[ -x "$LQ" ]] || return 2
  [[ -n "${LINEAR_API_KEY:-}" ]] || return 2

  # Backlog / Todo / In Progress / in Review いずれかに残っていれば既存扱い。
  # 全件スキャンは重いので最近 100 件から title 部分一致で拾う。
  local list
  list=$("$LQ" issue.list --team "$TEAM" --limit 100 2>/dev/null) || return 2

  local match
  match=$(echo "$list" | jq -r '
    map(select(
      (.title | test("\\[BLOCKED\\].*Codex.*(quota|rate.?limit|429)"; "i"))
      and ((.state.name | ascii_downcase) != "done"
           and (.state.name | ascii_downcase) != "canceled"
           and (.state.name | ascii_downcase) != "reviewed")
    )) | .[0].identifier // empty
  ' 2>/dev/null) || return 2

  if [[ -n "$match" ]]; then
    echo "$match"
    return 0
  fi
  return 1
}

# Linear に [BLOCKED] Codex quota チケットを起票する。
# 既存がある場合はその identifier を返して skip する。
create_blocked_issue() {
  local stderr_snippet="$1"
  local existing existing_status
  existing=$(existing_blocked_issue); existing_status=$?
  case "$existing_status" in
    0)
      err "既存の BLOCKED チケット: $existing — 起票 skip"
      echo "$existing"
      return 0
      ;;
    2)
      err "既存チェック失敗（Linear 接続不可など）— 起票はスキップ"
      return 1
      ;;
  esac
  # existing_status == 1: 既存なし → 新規起票へ

  if [[ "$DRY_RUN" == "1" ]]; then
    err "[DRY_RUN] BLOCKED チケットを新規起票する（実行スキップ）"
    return 0
  fi

  local body_file
  body_file=$(mktemp -t codex-blocked-body.XXXXXX)
  cat > "$body_file" <<EOF
## 検出経緯

\`scripts/codex/run.sh\` が Codex CLI 実行時に **quota / rate-limit / 429 / usage limit** に該当するエラーを検出しました。
親 subagent は exit code 42 で halt しています。

## 想定原因

- OpenAI API のクォータ枯渇（ChatGPT Plus 認証の月次上限到達 / API キーの月次予算超過）
- 短期的な rate limit（再試行で解消する可能性あり）

## 対応

1. \`~/.codex/auth.json\` を確認し、\`auth_mode\` と認証状況を確認
2. ChatGPT Plus 認証の場合: ブラウザで使用量を確認、必要なら翌日再試行
3. API キー認証の場合: OpenAI ダッシュボードで残予算を確認、必要に応じて課金 / 上限引き上げ
4. 解消後、本チケットを Done に遷移すれば自律パイプラインが再開

## 検出ログ抜粋

\`\`\`
$(printf '%s' "$stderr_snippet" | head -c 2000)
\`\`\`

## 自動起票元

\`scripts/codex/run.sh\` (KMD-123)
EOF

  # priority=1 (Urgent), label は付けない（label 名運用が team ごとに異なるため）
  local resp identifier
  if ! resp=$("$LQ" issue.create \
        --team "$TEAM" \
        --title "[BLOCKED] Codex quota / rate-limit detected" \
        --priority 1 \
        --body "@$body_file" 2>&1); then
    err "Linear 起票失敗: $resp"
    rm -f "$body_file"
    return 1
  fi
  rm -f "$body_file"

  identifier=$(echo "$resp" | jq -r '.identifier // empty' 2>/dev/null) || true
  if [[ -n "$identifier" ]]; then
    err "BLOCKED チケットを起票: $identifier"
    echo "$identifier"
  elif echo "$resp" | jq -e '.dryRun == true' >/dev/null 2>&1; then
    err "[LQ_DRY_RUN] BLOCKED チケット起票 payload を表示（実書き込みなし）"
  else
    err "起票したが identifier が取れず（応答: $resp）"
  fi
  return 0
}

main() {
  if [[ "${CODEX_RUN_LOGGED_BY_BUNDLE:-0}" != "1" ]]; then
    "${REPO_ROOT}/scripts/usage/log.sh" codex "run.sh" 0 "${CODEX_RUN_CONTEXT:-}" || true
  fi
  command -v jq >/dev/null || { err "jq が必要です (brew install jq)"; exit 2; }

  local stderr_file stdout_exit
  stderr_file=$(mktemp -t codex-run-stderr.XXXXXX)

  if [[ "$DRY_RUN" == "1" ]]; then
    err "[DRY_RUN] codex exec をスキップして stdin を読み捨て"
    cat > /dev/null
    log_run 0 "" ""
    rm -f "$stderr_file"
    exit 0
  fi

  if ! command -v codex >/dev/null; then
    err "codex CLI が見つかりません（PATH 設定を確認）"
    exit 2
  fi

  local codex_args=(
    exec
    -C "${CODEX_EXEC_CD:-$REPO_ROOT}"
    -s "${CODEX_EXEC_SANDBOX:-workspace-write}"
  )
  if [[ -n "${CODEX_EXEC_MODEL:-}" ]]; then
    codex_args+=(-m "$CODEX_EXEC_MODEL")
  fi
  codex_args+=(-)

  # codex exec を起動。stdout はそのまま親に渡す。stderr は tee で
  # ターミナルにも見せつつファイルにも捕捉する。
  set +e
  codex "${codex_args[@]}" 2> >(tee "$stderr_file" >&2)
  stdout_exit=$?
  set -e

  # quota / rate-limit / 429 / usage limit を検出する。
  # 注意: codex exit=0 のときは false positive 回避のため検出しない
  # （codex 側が内部リトライで成功した場合に警告だけ stderr に残るケースを除外）。
  local matched=""
  local stderr_snippet=""
  if [[ -s "$stderr_file" ]]; then
    stderr_snippet=$(tail -c 4000 "$stderr_file")
    if [[ "$stdout_exit" -ne 0 ]] && grep -E -i "$QUOTA_PATTERN" "$stderr_file" >/dev/null 2>&1; then
      matched="quota_pattern_in_stderr"
    fi
  fi

  # exit code が 0 以外でも quota パターンが出ていなければ普通の失敗扱い。
  log_run "$stdout_exit" "$matched" "$stderr_snippet"

  if [[ -n "$matched" ]]; then
    err "BLOCKED 検出: $matched (codex exit=$stdout_exit)"
    create_blocked_issue "$stderr_snippet" || err "BLOCKED チケット起票に失敗（処理は継続）"
    rm -f "$stderr_file"
    exit 42
  fi

  rm -f "$stderr_file"
  exit "$stdout_exit"
}

main "$@"
