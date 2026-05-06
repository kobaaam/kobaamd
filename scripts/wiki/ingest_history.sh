#!/usr/bin/env bash
set -euo pipefail

err() {
  echo "ingest_history.sh: $*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  ingest_history.sh append --status <status> [--ts <ISO8601>] [--source-count <N>]
  ingest_history.sh check [--threshold <N>] [--epic <KMD-XX>] [--dry-run]
  ingest_history.sh -h | --help

Subcommands:
  append    Append one JSONL record to .logs/wiki_ingest_history.jsonl
  check     Check trailing consecutive skipped/error records and optionally post to Linear

Options:
  --status <status>        One of: pass, pass-after-fix, violations, fail, error, skipped
  --ts <ISO8601>           Timestamp for append (default: local time via date)
  --source-count <N>       Source count for append (default: 0)
  --threshold <N>          Warning threshold for check (default: 5)
  --epic <KMD-XX>          Linear epic identifier for warning posts (default: KMD-44)
  --dry-run                Print generated warning markdown to stdout instead of posting
  -h, --help               Show this help
EOF
}

command -v jq >/dev/null 2>&1 || {
  err "jq required"
  exit 2
}

history_file=".logs/wiki_ingest_history.jsonl"

is_non_negative_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_valid_status() {
  case "$1" in
    pass|pass-after-fix|violations|fail|error|skipped)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

append_cmd() {
  local status=""
  local ts=""
  local source_count="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status)
        [[ $# -ge 2 ]] || {
          err "missing value for --status"
          exit 1
        }
        status="$2"
        shift 2
        ;;
      --ts)
        [[ $# -ge 2 ]] || {
          err "missing value for --ts"
          exit 1
        }
        ts="$2"
        shift 2
        ;;
      --source-count)
        [[ $# -ge 2 ]] || {
          err "missing value for --source-count"
          exit 1
        }
        source_count="$2"
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

  [[ -n "$status" ]] || {
    err "missing value for --status"
    exit 1
  }

  if ! is_valid_status "$status"; then
    err "unknown status"
    exit 1
  fi

  is_non_negative_integer "$source_count" || {
    err "source-count must be a non-negative integer"
    exit 1
  }

  if [[ -z "$ts" ]]; then
    ts="$(date +%Y-%m-%dT%H:%M:%S%z)"
  fi

  mkdir -p .logs
  jq -nc \
    --arg ts "$ts" \
    --arg lint_status "$status" \
    --argjson source_count "$source_count" \
    '{ts:$ts, lint_status:$lint_status, source_count:$source_count}' >> "$history_file"
}

build_warning_markdown() {
  local tail_status="$1"
  local consecutive="$2"
  local threshold="$3"

  cat <<EOF
## Wiki Ingest Gate Warning

\`kobaamd_update_wiki\` の lint ゲートが直近 ${consecutive} 回連続で \`${tail_status}\` 状態です（threshold=${threshold}）。

- 直近 status: \`${tail_status}\`
- 連続回数: ${consecutive}
- 閾値: ${threshold}
- history: \`.logs/wiki_ingest_history.jsonl\`

\`skipped\` が継続している場合は \`scripts/wiki/lint.sh\`（KMD-52）の整備状況を、\`error\` が継続している場合は lint 内部エラーを確認してください。
EOF
}

print_check_report() {
  local tail_status="$1"
  local consecutive="$2"
  local threshold="$3"
  local warning="$4"

  printf 'status=%s\n' "$tail_status"
  printf 'consecutive=%s\n' "$consecutive"
  printf 'threshold=%s\n' "$threshold"
  printf 'warning=%s\n' "$warning"
}

check_cmd() {
  local threshold="5"
  local epic="KMD-44"
  local dry_run=0
  local tail_status=""
  local consecutive="0"
  local warning="false"
  local check_json=""
  local comment_file=""
  local report=""

  cleanup() {
    if [[ -n "$comment_file" ]]; then
      rm -f "$comment_file"
    fi
  }
  trap cleanup EXIT

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold)
        [[ $# -ge 2 ]] || {
          err "missing value for --threshold"
          exit 1
        }
        threshold="$2"
        shift 2
        ;;
      --epic)
        [[ $# -ge 2 ]] || {
          err "missing value for --epic"
          exit 1
        }
        epic="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
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

  is_non_negative_integer "$threshold" || {
    err "threshold must be a non-negative integer"
    exit 1
  }

  if [[ -f "$history_file" && -s "$history_file" ]]; then
    check_json="$(
      jq -s '
        if length == 0 then
          {tail:"", consecutive:0}
        else
          .[-1].lint_status as $tail
          | if ($tail == "skipped" or $tail == "error") then
              {
                tail: $tail,
                consecutive: (
                  [range(length - 1; -1; -1) as $i | .[$i].lint_status]
                  | (map(. == $tail) | index(false) // length)
                )
              }
            else
              {tail: $tail, consecutive: 0}
            end
        end
      ' "$history_file"
    )"
    tail_status="$(printf '%s\n' "$check_json" | jq -r '.tail')"
    consecutive="$(printf '%s\n' "$check_json" | jq -r '.consecutive')"
  fi

  if [[ "$consecutive" -ge "$threshold" && -n "$tail_status" ]]; then
    warning="true"
  fi

  print_check_report "$tail_status" "$consecutive" "$threshold" "$warning"

  if [[ "$warning" != "true" ]]; then
    exit 0
  fi

  report="$(build_warning_markdown "$tail_status" "$consecutive" "$threshold")"

  if [[ "$dry_run" -eq 1 ]]; then
    printf '\n%s\n' "$report"
    exit 0
  fi

  comment_file="$(mktemp -t kobaamd_ingest_history_XXXX)"
  printf '%s\n' "$report" > "$comment_file"
  if ! ./scripts/linear/lq.sh comment.add "$epic" "@$comment_file" 1>&2; then
    err "failed to post Linear comment to $epic"
  fi
}

main() {
  [[ $# -gt 0 ]] || {
    usage
    exit 1
  }

  case "$1" in
    append)
      shift
      append_cmd "$@"
      ;;
    check)
      shift
      check_cmd "$@"
      ;;
    -h|--help)
      usage
      ;;
    *)
      err "unknown subcommand: $1"
      exit 1
      ;;
  esac
}

main "$@"
