#!/usr/bin/env bash
# Compare docs/llm-wiki frontmatter sources[].sha against git hash-object.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIKI="$ROOT/docs/llm-wiki"
WRITE=false
JSON=false
STRICT=false

usage() {
  echo "Usage: $0 [--json] [--write] [--strict]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=true ;;
    --write) WRITE=true ;;
    --strict) STRICT=true ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

if [[ ! -d "$WIKI" ]]; then
  echo "docs/llm-wiki not found" >&2
  exit 1
fi

stale=()
missing=()
errors=()
checked=0

while IFS= read -r -d '' page; do
  [[ "$page" == *"/_template.md" ]] && continue
  [[ "$page" == "$WIKI/README.md" ]] && continue
  [[ "$page" == "$WIKI/INDEX.md" ]] && continue
  [[ "$page" == "$WIKI/log.md" ]] && continue

  checked=$((checked + 1))
  page_stale=false

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    full="$ROOT/$path"
    if [[ ! -f "$full" ]]; then
      missing+=("$path (from $page)")
      continue
    fi
    expected=$(git -C "$ROOT" hash-object -- "$path" 2>/dev/null || true)
    recorded=$(awk -v p="$path" '
      /path:/ { path=$0; sub(/.*path:[[:space:]]*/, "", path); gsub(/"/, "", path) }
      path == p && /sha:/ { sha=$0; sub(/.*sha:[[:space:]]*/, "", sha); gsub(/"/, "", sha); print sha; exit }
    ' "$page")
    if [[ -z "$recorded" ]]; then
      errors+=("missing sha for $path in $page")
      continue
    fi
    if [[ "$recorded" != "$expected" ]]; then
      page_stale=true
    fi
  done < <(awk '/path:/ { gsub(/.*path:[[:space:]]*/, ""); gsub(/"/, ""); print }' "$page")

  if $page_stale; then
    stale+=("$page")
    if $WRITE; then
      if grep -q '^freshness:' "$page"; then
        sed -i '' 's/^freshness:.*/freshness: stale/' "$page" 2>/dev/null || \
          sed -i 's/^freshness:.*/freshness: stale/' "$page"
      fi
    fi
  fi
done < <(find "$WIKI" -name '*.md' -print0)

if $JSON; then
  printf '{"checked":%d,"stale":[' "$checked"
  first=true
  for s in "${stale[@]:-}"; do
    $first || printf ','
    first=false
    printf '"%s"' "${s#"$ROOT"/}"
  done
  printf '],"missing":['
  first=true
  for m in "${missing[@]:-}"; do
    $first || printf ','
    first=false
    printf '"%s"' "$m"
  done
  printf '],"errors":['
  first=true
  for e in "${errors[@]:-}"; do
    $first || printf ','
    first=false
    printf '"%s"' "$e"
  done
  printf ']}\n'
else
  echo "checked: $checked"
  [[ ${#stale[@]} -gt 0 ]] && printf 'stale:\n%s\n' "${stale[@]}"
  [[ ${#missing[@]} -gt 0 ]] && printf 'missing:\n%s\n' "${missing[@]}"
  [[ ${#errors[@]:-} -gt 0 ]] && printf 'errors:\n%s\n' "${errors[@]}"
fi

if $STRICT && { [[ ${#stale[@]} -gt 0 ]] || [[ ${#missing[@]} -gt 0 ]] || [[ ${#errors[@]:-} -gt 0 ]]; }; then
  exit 1
fi