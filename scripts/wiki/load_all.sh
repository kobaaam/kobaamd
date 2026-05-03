#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: load_all.sh [--include-raw] [-h|--help]' \
    '' \
    'Concatenate Markdown files under docs/wiki/articles to stdout.' \
    '' \
    'Options:' \
    '  --include-raw  Also include docs/wiki/raw if it exists.' \
    '  -h, --help     Show this help and exit.'
}

format_number() {
  awk -v n="$1" '
    function with_commas(value,    s, out) {
      s = sprintf("%.0f", value)
      while (s ~ /^[0-9]{4,}$/) {
        out = "," substr(s, length(s) - 2) out
        s = substr(s, 1, length(s) - 3)
      }
      return s out
    }
    BEGIN {
      printf "%s", with_commas(n)
    }
  '
}

include_raw=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --include-raw)
      include_raw=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  exit 1
fi

articles_dir="$ROOT/docs/wiki/articles"
raw_dir="$ROOT/docs/wiki/raw"

tmp_list=$(mktemp)
tmp_sorted=$(mktemp)

cleanup() {
  rm -f "$tmp_list" "$tmp_sorted"
}
trap cleanup EXIT

find "$articles_dir" -type f -name '*.md' -print >"$tmp_list"

if [ "$include_raw" -eq 1 ]; then
  if [ -d "$raw_dir" ]; then
    find "$raw_dir" -type f -name '*.md' -print >>"$tmp_list"
  else
    printf '%s\n' 'raw/ not found, skipping' >&2
  fi
fi

LC_ALL=C sort "$tmp_list" >"$tmp_sorted"

file_count=0
total_bytes=0

while IFS= read -r file_path; do
  [ -n "$file_path" ] || continue

  file_count=$((file_count + 1))
  file_bytes=$(wc -c <"$file_path" | awk '{print $1}')
  total_bytes=$((total_bytes + file_bytes))
  relative_path=${file_path#"$ROOT"/}

  printf '<!-- file: %s -->\n' "$relative_path"
  cat "$file_path"
  printf '\n\n'
done <"$tmp_sorted"

if [ "$file_count" -eq 0 ]; then
  printf '! ERROR: no markdown files found under %s\n' "$articles_dir" >&2
  exit 3
fi

rounded_kb=$(awk -v bytes="$total_bytes" 'BEGIN { printf "%.0f", bytes / 1024 }')
estimated_tokens=$(awk -v bytes="$total_bytes" 'BEGIN { printf "%.0f", bytes / 4 }')

formatted_kb=$(format_number "$rounded_kb")
formatted_tokens=$(format_number "$estimated_tokens")

printf '# Files: %s\n' "$file_count" >&2
printf '# Total: ~%skB / ~%s tokens\n' "$formatted_kb" "$formatted_tokens" >&2

if [ "$estimated_tokens" -gt 200000 ]; then
  printf '%s\n' \
    '! WARNING: estimated tokens exceed 200,000 (Anthropic prompt-cache budget). Consider trimming.' >&2
fi
