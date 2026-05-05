#!/usr/bin/env bash
set -euo pipefail

err() {
  echo "lint_report.sh: $*" >&2
}

usage() {
  cat <<'EOF'
Usage: lint_report.sh [options]

Read wiki lint NDJSON from stdin, summarize violations, and post a Linear comment.

Options:
  --epic <KMD-XX>       Linear epic identifier
  --threshold <N>       Post when violations are >= N (default: 1)
  --dry-run             Print markdown report to stdout instead of posting
  --report-title <s>    Report title
  -h, --help            Show this help
EOF
}

command -v jq >/dev/null 2>&1 || {
  err "jq required"
  exit 2
}

epic=""
threshold=1
dry_run=0
report_title=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic)
      [[ $# -ge 2 ]] || {
        err "missing value for --epic"
        exit 1
      }
      epic="$2"
      shift 2
      ;;
    --threshold)
      [[ $# -ge 2 ]] || {
        err "missing value for --threshold"
        exit 1
      }
      threshold="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --report-title)
      [[ $# -ge 2 ]] || {
        err "missing value for --report-title"
        exit 1
      }
      report_title="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown option: $1"
      exit 1
      ;;
  esac
done

[[ "$threshold" =~ ^[0-9]+$ ]] || {
  err "threshold must be a non-negative integer"
  exit 1
}

if [[ -z "$report_title" ]]; then
  report_title="Wiki Lint Report ($(date +%F) weekly)"
fi

valid_file="$(mktemp -t kmd54_XXXX)"
top_file="$(mktemp -t kmd54_XXXX)"
comment_file=""
cleanup() {
  rm -f "$valid_file" "$top_file"
  if [[ -n "$comment_file" ]]; then
    rm -f "$comment_file"
  fi
}
trap cleanup EXIT

total=0
top_count=0
input_line_no=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  input_line_no=$((input_line_no + 1))
  if [[ -z "${raw_line//[[:space:]]/}" ]]; then
    continue
  fi

  if ! printf '%s\n' "$raw_line" | jq -e . >/dev/null 2>&1; then
    err "warning: invalid JSON on input line $input_line_no"
    continue
  fi

  if ! normalized_line="$(printf '%s\n' "$raw_line" | jq -ce . 2>/dev/null)"; then
    err "warning: failed to normalize JSON on input line $input_line_no"
    continue
  fi

  printf '%s\n' "$normalized_line" >> "$valid_file"
  total=$((total + 1))

  if [[ "$top_count" -lt 5 ]]; then
    printf '%s\n' "$normalized_line" >> "$top_file"
    top_count=$((top_count + 1))
  fi
done

if [[ "$total" -eq 0 ]]; then
  exit 0
fi

if [[ "$total" -lt "$threshold" ]]; then
  err "below threshold: total=$total threshold=$threshold"
  exit 0
fi

rule_rows="$(
  jq -sr '
    group_by(.rule)
    | map({rule: .[0].rule, count: length})
    | sort_by([-(.count), .rule])
    | map("| \(.rule) | \(.count) |")
    | join("\n")
  ' "$valid_file"
)"

top_rows="$(
  jq -sr '
    map(
      .detail |= (
        tostring
        | gsub("\r"; " ")
        | gsub("\n"; " ")
        | gsub("\\|"; "\\|")
        | if length > 120 then .[:117] + "..." else . end
      )
      | .line = (.line // "-")
      | "| \(.file) | \(.rule) | \(.line) | \(.detail) |"
    )
    | join("\n")
  ' "$top_file"
)"

report="$(
  {
    printf '## %s\n\n' "$report_title"
    printf '`/kobaamd_lint_wiki` で違反 %s 件を検出しました。\n\n' "$total"
    printf '### ルール別件数\n\n'
    printf '| rule | count |\n'
    printf '|---|---|\n'
    if [[ -n "$rule_rows" ]]; then
      printf '%s\n' "$rule_rows"
    fi
    printf '\n### 上位 5 件\n\n'
    printf '| file | rule | line | detail |\n'
    printf '|---|---|---|---|\n'
    if [[ -n "$top_rows" ]]; then
      printf '%s\n' "$top_rows"
    fi
    printf '\n詳細 NDJSON は weekly ジョブログを参照: `.logs/pipeline_weekly.log`\n\n'
    printf '→ 修正は手動で個別チケットに分解してください。\n'
  }
)"

resolve_epic() {
  local resolved=""

  if [[ -n "$epic" ]]; then
    printf '%s\n' "$epic"
    return
  fi

  if resolved="$(
    ./scripts/linear/lq.sh issue.list --team KMD --limit 250 2>/dev/null \
      | jq -r '.[] | select(.title | contains("[KB] kobaamd ナレッジベース整備")) | .identifier' \
      | head -n 1
  )"; then
    if [[ -n "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return
    fi
  fi

  err "epic not found via title search, falling back to KMD-44"
  printf 'KMD-44\n'
}

if [[ "$dry_run" -eq 1 ]]; then
  printf '%s' "$report"
  exit 0
fi

epic="$(resolve_epic)"
comment_file="$(mktemp -t kmd54_XXXX)"
printf '%s' "$report" > "$comment_file"

err "posting Linear comment to $epic"
if [[ "${LQ_DRY_RUN:-0}" == "1" ]]; then
  if ! ./scripts/linear/lq.sh comment.add "$epic" "@$comment_file"; then
    err "failed to post Linear comment"
  fi
else
  if ! ./scripts/linear/lq.sh comment.add "$epic" "@$comment_file" 1>&2; then
    err "failed to post Linear comment"
  fi
fi

exit 0
