#!/usr/bin/env bash
set -euo pipefail

# scripts/wiki/detect-deleted-sources.sh
#
# Detect wiki articles that reference deleted Sources/ files.
#
# Usage:
#   scripts/wiki/detect-deleted-sources.sh [--since <commit-or-date>]
#
# Options:
#   --since <value>  Git commit hash or date string passed to `git log --since`.
#                    Default: "7 days ago"
#
# Output:
#   Human-readable report to stdout. When stale references are found, each
#   wiki article path is printed with the deleted source file it references.
#
# Exit codes:
#   0  no stale references found
#   1  one or more stale references found
#   2  internal error

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WIKI_DIR="$ROOT/docs/wiki/articles"
SOURCES_PREFIX="Sources/"

# --- Argument parsing -------------------------------------------------------

SINCE="7 days ago"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      shift
      if [[ $# -eq 0 ]]; then
        printf 'detect-deleted-sources.sh: --since requires an argument\n' >&2
        exit 2
      fi
      SINCE="$1"
      shift
      ;;
    -h|--help)
      sed -n '/^#/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      printf 'detect-deleted-sources.sh: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

# --- Collect deleted Sources/ files -----------------------------------------

cd "$ROOT"

# git log --diff-filter=D lists files deleted in the given range.
# --name-only + --format="" suppresses commit headers so we get plain paths.
deleted_sources=()
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  [[ "$path" == "$SOURCES_PREFIX"* ]] || continue
  deleted_sources+=("$path")
done < <(git log --since="$SINCE" --diff-filter=D --name-only --format="" -- "$SOURCES_PREFIX" 2>/dev/null)

if [[ ${#deleted_sources[@]} -eq 0 ]]; then
  printf 'detect-deleted-sources.sh: no deleted Sources/ files found in the given range (--since "%s")\n' "$SINCE"
  exit 0
fi

printf 'detect-deleted-sources.sh: found %d deleted Sources/ file(s) in the given range\n' "${#deleted_sources[@]}"

# --- Grep wiki articles for references to deleted files ---------------------

stale_found=0

if [[ ! -d "$WIKI_DIR" ]]; then
  printf 'detect-deleted-sources.sh: wiki articles directory not found: %s\n' "$WIKI_DIR" >&2
  exit 2
fi

# Use a temp file to accumulate results (avoids bash 3 associative array limitation)
RESULT_TMP=$(mktemp)
trap 'rm -f "$RESULT_TMP"' EXIT

for deleted in "${deleted_sources[@]}"; do
  # Escape special regex characters in the path for grep
  pattern=$(printf '%s' "$deleted" | sed 's/[.[\*^$]/\\&/g')

  while IFS= read -r article; do
    [[ -z "$article" ]] && continue
    rel_article="${article#"$ROOT"/}"
    printf '%s\t%s\n' "$rel_article" "$deleted" >> "$RESULT_TMP"
    stale_found=1
  done < <(grep -rl "$pattern" "$WIKI_DIR" 2>/dev/null || true)
done

# --- Report -----------------------------------------------------------------

if [[ $stale_found -eq 0 ]]; then
  printf 'detect-deleted-sources.sh: no stale references found in wiki articles\n'
  exit 0
fi

printf '\n=== Stale wiki references to deleted Sources/ files ===\n\n'

# Sort and deduplicate, then group by article
sort -u "$RESULT_TMP" | awk -F'\t' '
  {
    if ($1 != prev) {
      if (prev != "") printf "\n"
      printf "Article: %s\n", $1
      prev = $1
    }
    printf "  references deleted: %s\n", $2
  }
  END { if (prev != "") printf "\n" }
'

printf 'Action: review and remove or update these references.\n'
exit 1
