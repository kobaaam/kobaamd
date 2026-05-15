#!/usr/bin/env bash
# check-cli-args.sh — claude -p の variadic option 後置バグを検出する lint
#
# Commander.js の variadic option は、後続の位置引数まで貪欲に取り込む。
# claude -p --allowedTools <tools> "$prompt" のような呼び出しを検出し、
# stdin 経由の呼び出しへ逃がすことを促す。

set -uo pipefail

SCRIPT_NAME="[check-cli-args]"
VARIADIC_OPTIONS=(
  "--allowedTools"
  "--mcp-config"
  "--allowedDirs"
  "--disallowedTools"
)

usage() {
  echo "Usage: scripts/lint/check-cli-args.sh [--staged] [file ...]" >&2
}

error() {
  echo "$SCRIPT_NAME ERROR: $*" >&2
  exit 2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "required command not found: $1"
  fi
}

is_shell_file() {
  case "$1" in
    *.sh) return 0 ;;
    *) return 1 ;;
  esac
}

is_comment_line() {
  [[ "$1" =~ ^[[:space:]]*# ]]
}

ends_with_continuation() {
  [[ "$1" =~ \\[[:space:]]*$ ]]
}

strip_continuation_marker() {
  if ends_with_continuation "$1"; then
    printf '%s\n' "$1" | sed 's/[[:space:]]*\\[[:space:]]*$//'
  else
    printf '%s\n' "$1"
  fi
}

contains_claude_print() {
  [[ "$1" =~ (^|[[:space:];&])claude[[:space:]]+(-p|--print)([[:space:]]|$) ]]
}

uses_stdin_pipe_to_claude_print() {
  [[ "$1" =~ \|[[:space:]]*claude[[:space:]]+(-p|--print)([[:space:]]|$) ]]
}

contains_variadic_violation() {
  local logical_line="$1"
  local option
  local non_option='("[^"]*"|'\''[^'\'']*'\''|\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]+\}|[^-[:space:]\\][^[:space:]\\]*)'

  if ! contains_claude_print "$logical_line"; then
    return 1
  fi

  if uses_stdin_pipe_to_claude_print "$logical_line"; then
    return 1
  fi

  for option in "${VARIADIC_OPTIONS[@]}"; do
    if [[ "$logical_line" =~ (^|[[:space:]])"$option"[[:space:]]+$non_option[[:space:]]+$non_option ]]; then
      return 0
    fi
  done

  return 1
}

report_violation() {
  local file="$1"
  local line_number="$2"
  local line_content="$3"

  echo "$SCRIPT_NAME VIOLATION detected: $file:$line_number"
  echo "  $line_content"
  echo "Fix: variadic option の後に位置引数を置かないこと。"
  echo "     stdin 経由 (printf '%s' \"\$prompt\" | claude -p ...) に変更してください。"
}

check_file() {
  local file="$1"
  local line
  local logical_part
  local line_number=0
  local logical_line=""
  local logical_start=0
  local violations=0

  if [ ! -f "$file" ]; then
    return 0
  fi

  if ! grep -qE '(^|[[:space:];&|])claude[[:space:]]+(-p|--print)([[:space:]]|$)' "$file"; then
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))

    if [ -z "$logical_line" ]; then
      if is_comment_line "$line"; then
        continue
      fi
      logical_start=$line_number
      logical_part=$(strip_continuation_marker "$line")
      logical_line="$logical_part"
    else
      logical_part=$(strip_continuation_marker "$line")
      logical_line="$logical_line $logical_part"
    fi

    if ends_with_continuation "$line"; then
      continue
    fi

    if contains_variadic_violation "$logical_line"; then
      report_violation "$file" "$logical_start" "$logical_line"
      violations=$((violations + 1))
    fi

    logical_line=""
    logical_start=0
  done < "$file"

  if [ -n "$logical_line" ] && contains_variadic_violation "$logical_line"; then
    report_violation "$file" "$logical_start" "$logical_line"
    violations=$((violations + 1))
  fi

  if [ "$violations" -gt 0 ]; then
    return 1
  fi
  return 0
}

collect_all_shell_files() {
  find . -path './.git' -prune -o -type f -name '*.sh' -print
}

collect_staged_shell_files() {
  git diff --cached --name-only --diff-filter=ACMR | grep '\.sh$' || true
}

main() {
  local staged=0
  local explicit_seen=0
  local files=()
  local file
  local file_count=0
  local violations=0

  require_command grep
  require_command git
  require_command find
  require_command sed

  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    error "not inside a git repository"
  fi

  cd "$(git rev-parse --show-toplevel)" || error "failed to cd to repository root"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --staged)
        staged=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --*)
        usage
        error "unknown option: $1"
        ;;
      *)
        explicit_seen=1
        if is_shell_file "$1"; then
          files+=("$1")
          file_count=$((file_count + 1))
        fi
        ;;
    esac
    shift
  done

  if [ "$staged" -eq 1 ] && [ "$explicit_seen" -eq 1 ]; then
    error "--staged cannot be combined with explicit files"
  fi

  if [ "$staged" -eq 1 ]; then
    while IFS= read -r file; do
      if [ -n "$file" ]; then
        files+=("$file")
        file_count=$((file_count + 1))
      fi
    done < <(collect_staged_shell_files)
  elif [ "$explicit_seen" -eq 0 ]; then
    while IFS= read -r file; do
      if [ -n "$file" ]; then
        files+=("$file")
        file_count=$((file_count + 1))
      fi
    done < <(collect_all_shell_files)
  fi

  if [ "$file_count" -gt 0 ]; then
    for file in "${files[@]}"; do
      if ! check_file "$file"; then
        violations=$((violations + 1))
      fi
    done
  fi

  if [ "$violations" -gt 0 ]; then
    exit 1
  fi

  echo "$SCRIPT_NAME OK: no violations found."
  exit 0
}

main "$@"
