#!/usr/bin/env bash
# scripts/launchd/preflight_check.sh
#
# kobaamd_pipeline_active を起動するべきか判定する pre-flight check。
# launchd が 30 分毎に呼ぶ run_bundle.sh の前段で動作し、対象 issue がゼロなら
# Codex の起動を skip してメインセッションのトークン消費を 0 にする。
#
# Exit code:
#   0  proceed: pipeline_active を起動する
#   1  skip:    対象 issue ゼロのため起動しない
#   2  error:   preflight 自体が失敗（fail-open: caller は proceed 扱いにする）
#
# stdout に判定結果サマリを 1 行出力。run_bundle.sh がログに転記する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOBAAMD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$KOBAAMD_DIR"

# launchd の最小環境で codex / gh / jq が PATH に無い対策（run_bundle.sh と同じ）。
# zshrc を bash で source すると zsh 専用構文で parse error → 即終了するので、
# 必要な変数だけ zsh から export 形式で取り出して eval する。
# PATH は .zprofile / .zshenv で定義されているので zsh -lc で取れる。
# LINEAR_API_KEY は .zshrc で定義されているので zsh -ic（interactive）で取る。
eval "$(zsh -lc 'echo "export PATH=\"$PATH\""' 2>/dev/null)" || true
eval "$(zsh -ic 'echo "export LINEAR_API_KEY=\"${LINEAR_API_KEY:-}\""' 2>/dev/null)" || true

LQ="$KOBAAMD_DIR/scripts/linear/lq.sh"

# 各状態の issue 件数を取得（lq.sh の標準出力が JSON 配列）。
# 失敗時は -1 を返して fail-open に倒す。
count_state() {
  local state="$1"
  local out
  out=$("$LQ" issue.list --team KMD --state "$state" --limit 50 2>/dev/null) || return 1
  echo "$out" | jq 'length' 2>/dev/null
}

# docs-only learnings/postmortem PRs can remain open after the parent issue is
# Done. Those follow-up PRs are not actionable work for pipeline_active, so
# ignore them when deciding whether conflicting PRs should wake the bundle.
count_actionable_conflicting_prs() {
  local prs conflicting_branches branch issue_id issue_state
  local actionable=0
  local ignored=0

  prs=$(gh pr list --state open --limit 200 --json mergeable,headRefName 2>/dev/null) || return 1
  conflicting_branches=$(echo "$prs" | jq -r '.[] | select(.mergeable == "CONFLICTING") | .headRefName' 2>/dev/null) || return 1

  if [[ -z "$conflicting_branches" ]]; then
    ACTIONABLE_CONFLICTING=0
    IGNORED_STALE_LEARNINGS=0
    return 0
  fi

  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue

    if [[ "$branch" =~ ^feature/learnings-(KMD-[0-9]+)$ ]]; then
      issue_id="${BASH_REMATCH[1]}"
      issue_state=$("$LQ" issue.get "$issue_id" 2>/dev/null | jq -r '.state.name' 2>/dev/null) || return 1
      if [[ "$issue_state" == "Done" ]]; then
        ignored=$((ignored + 1))
        continue
      fi
    fi

    actionable=$((actionable + 1))
  done <<< "$conflicting_branches"

  ACTIONABLE_CONFLICTING=$actionable
  IGNORED_STALE_LEARNINGS=$ignored
}

REVIEWED=$(count_state "Reviewed")        || REVIEWED=-1
HUMAN=$(count_state "Human in Review")    || HUMAN=-1
IN_REVIEW=$(count_state "in Review")      || IN_REVIEW=-1
DRAFT=$(count_state "draft")              || DRAFT=-1
TODO=$(count_state "Todo")                || TODO=-1
IN_PROGRESS=$(count_state "In Progress")  || IN_PROGRESS=-1

# CONFLICTING PR を gh で確認
ACTIONABLE_CONFLICTING=0
IGNORED_STALE_LEARNINGS=0
count_actionable_conflicting_prs || ACTIONABLE_CONFLICTING=-1
CONFLICTING="$ACTIONABLE_CONFLICTING"

# 1 つでも -1（取得失敗）が混じっていれば fail-open
if [[ "$REVIEWED" == "-1" ]] || [[ "$HUMAN" == "-1" ]] || [[ "$IN_REVIEW" == "-1" ]] \
   || [[ "$DRAFT" == "-1" ]] || [[ "$TODO" == "-1" ]] || [[ "$IN_PROGRESS" == "-1" ]] \
   || [[ "$CONFLICTING" == "-1" ]]; then
  echo "PREFLIGHT_ERROR: Linear API or gh CLI fetch failed (fail-open, will proceed). reviewed=$REVIEWED human=$HUMAN in_review=$IN_REVIEW draft=$DRAFT todo=$TODO in_progress=$IN_PROGRESS conflicting=$CONFLICTING ignored_stale_learnings=$IGNORED_STALE_LEARNINGS"
  exit 2
fi

# proceed 条件（OR）
# 1. Reviewed > 0           — merge_pr 対象あり
# 2. Human in Review > 0    — フェーズ A ステップ 4 の人間コメント検査が必要
#    （new comment あり/なしの厳密判定は pipeline_active 内に委ねる）
# 3. in Review > 0          — review_pr の継続 / fix_pr_comments の対象
# 4. CONFLICTING > 0        — コンフリクト解消の対象
# 5. draft > 0              — create_prd の対象
# 6. Todo > 0 かつ In Progress = 0 — 新規実装に進める状態（WIP=1）
PROCEED_REASON=""
if [[ "$REVIEWED" -gt 0 ]]; then
  PROCEED_REASON="reviewed=$REVIEWED"
elif [[ "$HUMAN" -gt 0 ]]; then
  PROCEED_REASON="human_in_review=$HUMAN"
elif [[ "$IN_REVIEW" -gt 0 ]]; then
  PROCEED_REASON="in_review=$IN_REVIEW"
elif [[ "$CONFLICTING" -gt 0 ]]; then
  PROCEED_REASON="conflicting=$CONFLICTING"
elif [[ "$DRAFT" -gt 0 ]]; then
  PROCEED_REASON="draft=$DRAFT"
elif [[ "$TODO" -gt 0 ]] && [[ "$IN_PROGRESS" -eq 0 ]]; then
  PROCEED_REASON="todo=$TODO in_progress=0"
fi

if [[ -n "$PROCEED_REASON" ]]; then
  echo "PREFLIGHT_PROCEED: $PROCEED_REASON (reviewed=$REVIEWED human=$HUMAN in_review=$IN_REVIEW draft=$DRAFT todo=$TODO in_progress=$IN_PROGRESS conflicting=$CONFLICTING ignored_stale_learnings=$IGNORED_STALE_LEARNINGS)"
  exit 0
fi

# active pipeline が今この run で処理すべき actionable queue がない
echo "PREFLIGHT_SKIP: no actionable queue (reviewed=$REVIEWED human=$HUMAN in_review=$IN_REVIEW draft=$DRAFT todo=$TODO in_progress=$IN_PROGRESS conflicting=$CONFLICTING ignored_stale_learnings=$IGNORED_STALE_LEARNINGS)"
exit 1
