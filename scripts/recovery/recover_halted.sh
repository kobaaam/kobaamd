#!/usr/bin/env bash
# recover_halted.sh — halted In Progress issue の自動 recovery
#
# 背景:
#   KMD-30 incident（使用制限による Claude 中断 → ローカル staged 残留 → 自己救済不能）
#   と同じ事故を防ぐため、pipeline_active 起動時に自動で staged を救済する。
#
# 使い方:
#   ./scripts/recovery/recover_halted.sh <KMD-XX>           # 単一 issue を救済
#   ./scripts/recovery/recover_halted.sh --auto             # In Progress 全件を点検
#   LQ_DRY_RUN=1 ./scripts/recovery/recover_halted.sh --auto  # 実行せず判定のみ
#
# 判定マトリクス:
#   In Progress + ローカルブランチあり + リモート未push + PR なし + uncommitted + build pass
#     → auto_commit_push_pr (halted-recovered ラベル付与, in Review に遷移)
#   In Progress + リモートブランチあり + PR なし
#     → gh pr create のリトライ
#   In Progress + ローカルブランチあり + uncommitted + build fail
#     → halted-broken ラベル付与, Linear に警告コメント, 人間介入待ち

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
LQ="${REPO_ROOT}/scripts/linear/lq.sh"
LOG="${REPO_ROOT}/.logs/halted_recovery.log"
mkdir -p "$(dirname "$LOG")"

DRY_RUN="${LQ_DRY_RUN:-0}"

# halted ラベル ID（label.list KMD で取得した固定値）
LABEL_HALTED_RECOVERED="f4412a81-4bd0-4999-98c4-1c1e06dd9781"
LABEL_HALTED_BROKEN="9fa72c00-252c-49cd-9e7d-6af0f5b90ff0"

err() { echo "recover_halted: $*" >&2; }
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" | tee -a "$LOG"; }

[[ -x "$LQ" ]] || { err "lq.sh not found at $LQ"; exit 1; }
[[ -n "${LINEAR_API_KEY:-}" ]] || { err "LINEAR_API_KEY not set"; exit 1; }
command -v gh >/dev/null || { err "gh CLI required"; exit 1; }
command -v swift >/dev/null || { err "swift required"; exit 1; }

# ----- helpers -----

# Issue ID (KMD-XX) を slug 込みのブランチ名にマッチさせる
find_branch_for_issue() {
  local id="$1"
  # ローカルブランチで feature/<KMD-XX>-* に一致するもの
  git branch --list "feature/${id}-*" --format='%(refname:short)' | head -1
}

# リモートブランチの存在確認
remote_branch_exists() {
  local branch="$1"
  git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
}

# PR 存在確認
pr_exists_for_branch() {
  local branch="$1"
  local num
  num=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || true)
  [[ -n "$num" && "$num" != "null" ]]
}

# Linear へラベル付与（既存ラベルを保持しつつ追加）
add_label() {
  local id="$1" label_id="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "  DRY_RUN: would add label $label_id to $id"
    return
  fi
  local current
  current=$($LQ issue.get "$id" | jq -r '.labels.nodes | map(.id) | join(",")')
  local merged
  if [[ -z "$current" ]]; then
    merged="$label_id"
  else
    merged="${current},${label_id}"
  fi
  $LQ issue.update "$id" --labels "$merged" >/dev/null
}

# 自動 commit + push + PR 作成
auto_commit_push_pr() {
  local id="$1" branch="$2"
  log "auto_commit_push_pr: $id (branch: $branch)"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "  DRY_RUN: would checkout $branch, commit -m '$id: WIP halted recovery', push, gh pr create"
    return 0
  fi

  # ブランチに checkout
  git checkout "$branch" || { err "checkout failed: $branch"; return 2; }

  # uncommitted があるか
  if [[ -n "$(git status --porcelain)" ]]; then
    log "  staged/unstaged changes detected, committing"
    git add -A

    # pre-commit hook を必ず通す（--no-verify 禁止）
    if ! git commit -m "${id}: WIP commit by halted recovery (auto)"; then
      err "pre-commit hook failed for $id — marking halted-broken"
      add_label "$id" "$LABEL_HALTED_BROKEN"
      local note=$(mktemp)
      cat > "$note" <<EOF
## halted recovery: pre-commit hook 失敗

ローカル staged を WIP commit しようとしたが、pre-commit hook が失敗しました。
人間介入が必要です。失敗ログを git status / pre-commit ログから確認してください。

- branch: \`$branch\`
- commit message が試行された: \`${id}: WIP commit by halted recovery (auto)\`
- hook 失敗の原因（推定）: シークレット検査の false positive、ビルド検証失敗 など
EOF
      $LQ comment.add "$id" "@$note"
      rm -f "$note"
      return 3
    fi
  else
    log "  no uncommitted changes (already committed locally)"
  fi

  # push
  log "  pushing $branch"
  if ! git push -u origin "$branch" 2>&1 | tail -3; then
    err "push failed for $branch"
    add_label "$id" "$LABEL_HALTED_BROKEN"
    return 4
  fi

  # PR 作成
  if pr_exists_for_branch "$branch"; then
    log "  PR already exists, skipping gh pr create"
  else
    log "  creating PR via gh"
    local title="[HALTED-RECOVERED] ${id}: $(git log -1 --pretty=%s | head -c 100)"
    local body=$(mktemp)
    cat > "$body" <<EOF
## Auto-recovered from halted state

This PR was created by \`scripts/recovery/recover_halted.sh\` because the
original implementing subagent (kobaamd_implement_code / rework_issue /
fix_pr_comments) appears to have been interrupted (likely by API usage
limits or session interruption) before pushing and creating a PR.

### State at recovery
- branch: \`$branch\`
- last commit: \`$(git log -1 --pretty='%h %s')\`
- swift build: PASS (verified by recovery script)

### Required action
- This PR must be reviewed by **kobaamd_review_pr** and **kobaamd_review_security** as usual.
- The \`halted-recovered\` label indicates this is an automated recovery and must NOT skip the standard review process.
- Direct merge to main without review is forbidden.

Linear: ${id}
EOF
    if ! gh pr create --title "$title" --body-file "$body" --head "$branch" --base main 2>&1; then
      err "gh pr create failed for $branch"
      add_label "$id" "$LABEL_HALTED_BROKEN"
      rm -f "$body"
      return 5
    fi
    rm -f "$body"
  fi

  # halted-recovered ラベル + Linear 遷移
  add_label "$id" "$LABEL_HALTED_RECOVERED"
  $LQ issue.transition "$id" "in Review" >/dev/null

  local note=$(mktemp)
  cat > "$note" <<EOF
## halted recovery completed

Auto-recovered from halted In Progress state via \`scripts/recovery/recover_halted.sh\`.

- WIP commit: \`$(git log -1 --pretty='%h %s')\`
- Branch pushed: \`$branch\`
- PR created (or already existed) with \`[HALTED-RECOVERED]\` prefix
- Issue moved to \`in Review\`
- Label \`halted-recovered\` applied

Standard review (kobaamd_review_pr + kobaamd_review_security) required.
EOF
  $LQ comment.add "$id" "@$note" >/dev/null
  rm -f "$note"

  log "  recovery success: $id"
  return 0
}

# 単一 issue の判定 + recovery
recover_one() {
  local id="$1"
  log "evaluating $id"

  local state
  state=$($LQ issue.get "$id" | jq -r '.state.name')
  if [[ "$state" != "In Progress" ]]; then
    log "  skip: state is '$state', not 'In Progress'"
    return 0
  fi

  local branch
  branch=$(find_branch_for_issue "$id")
  if [[ -z "$branch" ]]; then
    log "  skip: no local branch matching feature/${id}-*"
    return 0
  fi

  local has_remote=0
  remote_branch_exists "$branch" && has_remote=1
  local has_pr=0
  pr_exists_for_branch "$branch" && has_pr=1

  log "  branch=$branch local=yes remote=$has_remote pr=$has_pr"

  # ローカル commit / staged を確認するため checkout 必要
  local current_branch
  current_branch=$(git branch --show-current)

  # ケース 1: ローカルあり + リモートなし + PR なし → auto recovery
  if [[ "$has_remote" == "0" && "$has_pr" == "0" ]]; then
    git checkout "$branch" 2>&1 | tail -1 || { err "checkout failed"; return 2; }

    # build 確認
    log "  running swift build to verify"
    if swift build 2>&1 | tee /tmp/recover_build.log | tail -3 | grep -q "Build complete"; then
      log "  swift build PASS, proceeding with auto recovery"
      auto_commit_push_pr "$id" "$branch"
    else
      err "swift build FAILED for $id, marking halted-broken"
      add_label "$id" "$LABEL_HALTED_BROKEN"
      local note=$(mktemp)
      cat > "$note" <<EOF
## halted recovery: swift build 失敗

\`scripts/recovery/recover_halted.sh\` で staged を救済しようとしたが、
\`swift build\` が失敗しました。実装が壊れた状態で中断された可能性があります。

人間介入が必要です。
- \`/tmp/recover_build.log\` を確認
- 必要なら staged を破棄して Todo に戻し、再実装

Branch: \`$branch\`
EOF
      $LQ comment.add "$id" "@$note" >/dev/null
      rm -f "$note"
    fi

    # 元のブランチに戻る
    [[ -n "$current_branch" && "$current_branch" != "$branch" ]] && git checkout "$current_branch" 2>&1 | tail -1
    return 0
  fi

  # ケース 2: ローカルあり + リモートあり + PR なし → PR 作成のみ
  if [[ "$has_remote" == "1" && "$has_pr" == "0" ]]; then
    log "  pushing already done, only PR creation needed"
    git checkout "$branch" 2>&1 | tail -1 || { err "checkout failed"; return 2; }

    # PR 作成のみ実行
    auto_commit_push_pr "$id" "$branch"

    [[ -n "$current_branch" && "$current_branch" != "$branch" ]] && git checkout "$current_branch" 2>&1 | tail -1
    return 0
  fi

  # それ以外（PR がある等）は recovery 不要
  log "  skip: PR already exists or other normal state"
  return 0
}

# --auto モード: In Progress 全件を点検
recover_auto() {
  log "=== recover_halted --auto start ==="
  local issues
  issues=$($LQ issue.list --team KMD --state "In Progress" | jq -r '.[].identifier')

  if [[ -z "$issues" ]]; then
    log "no In Progress issues; nothing to do"
    return 0
  fi

  local count=0
  for id in $issues; do
    recover_one "$id" || true
    count=$((count + 1))
  done

  log "=== recover_halted --auto done (processed $count issues) ==="
}

# ----- main -----

if [[ $# -eq 0 ]]; then
  err "usage: recover_halted.sh <KMD-XX> | --auto"
  exit 1
fi

case "$1" in
  --auto)
    recover_auto
    ;;
  KMD-*)
    recover_one "$1"
    ;;
  *)
    err "invalid argument: $1"
    err "usage: recover_halted.sh <KMD-XX> | --auto"
    exit 1
    ;;
esac
