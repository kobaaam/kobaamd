#!/usr/bin/env bash
set -euo pipefail

# scripts/wiki/lint.sh
#
# Lint kobaamd LLM Wiki articles under docs/wiki/articles/ against the rules
# documented in docs/wiki/SCHEMA.md "## 記載規約".
#
# Five rules are evaluated:
#   1. orphan          — article not linked from index.md nor any other Related
#   2. broken-link     — [[wikilink]] target does not exist
#   3. stale           — `updated` older than 60 days AND newer source files exist
#   4. section-context-missing — H2/H3 section unclear without article title
#                        (Claude Code subagent `kobaamd_lint_section_context`,
#                        model: haiku. Mandatory unless --no-llm. Use
#                        --legacy-api to fall back to direct Anthropic API.)
#   5. frontmatter     — required field missing / tag naming / Related symmetry
#
# Output: NDJSON to stdout, one violation per line:
#   {"file":"...","rule":"...","line":<int|null>,"detail":"...","model":"shell"|"haiku"}
#
# Exit codes:
#   0  no violations
#   1  violations found
#   2  internal error
#
# Usage:
#   scripts/wiki/lint.sh [options] [path ...]
#
# Options:
#   --no-llm         Skip rule 4 (Haiku-based section context check)
#   --fix            Apply automatic fixes for tag normalization and missing
#                    frontmatter fields. Edits files in-place.
#   --cache <path>   Path for the section-context content_hash cache.
#                    Default: .cache/wiki-lint.json (under repo root)
#   --report <path>  Path for the execution report JSON.
#                    Default: .cache/wiki-lint-report.json (under repo root)
#   --model <id>     Haiku model id (legacy path only; default: claude-haiku-4-5)
#   --retries <n>    Retry count for Haiku calls (default: 3)
#   --legacy-api     Use direct Anthropic API for rule 4 (requires
#                    ANTHROPIC_API_KEY). Default route is the
#                    `kobaamd_lint_section_context` Claude Code subagent.
#   -h, --help       Show this help and exit

err() { printf 'lint.sh: %s\n' "$*" >&2; }
log() { printf 'lint.sh: %s\n' "$*" >&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 2
  fi
}

usage() {
  cat <<'EOF' >&2
Usage: lint.sh [options] [path ...]

Without paths, lints every file under docs/wiki/articles/.
Paths may be article files or subdirectories under docs/wiki/articles/.

Options:
  --no-llm         Skip rule 4 (Haiku-based section context check)
  --fix            Apply auto-fixes (tag normalization, frontmatter defaults)
  --cache <path>   Section-context cache file (default: .cache/wiki-lint.json)
  --report <path>  Execution report JSON (default: .cache/wiki-lint-report.json)
  --model <id>     Haiku model id (legacy path only; default: claude-haiku-4-5)
  --retries <n>    Retry count for Haiku calls (default: 3)
  --legacy-api     Use direct Anthropic API (requires ANTHROPIC_API_KEY).
                   Default route is the kobaamd_lint_section_context subagent.
  -h, --help       Show this help

Output: NDJSON on stdout (1 violation = 1 line).
Exit:   0 = clean, 1 = violations, 2 = internal error.
EOF
}

# --- Args -------------------------------------------------------------------

no_llm=0
do_fix=0
cache_path=""
report_path=""
model="${ANTHROPIC_HAIKU_MODEL:-claude-haiku-4-5}"
retries=3
legacy_api=0
paths=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-llm) no_llm=1; shift ;;
    --fix) do_fix=1; shift ;;
    --cache)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      cache_path="$2"; shift 2 ;;
    --report)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      report_path="$2"; shift 2 ;;
    --model)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      model="$2"; shift 2 ;;
    --retries)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      retries="$2"; shift 2 ;;
    --legacy-api) legacy_api=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ "$#" -gt 0 ]; do paths+=("$1"); shift; done ;;
    -*) err "unknown option: $1"; usage; exit 2 ;;
    *) paths+=("$1"); shift ;;
  esac
done

# --- Environment ------------------------------------------------------------

require_cmd jq
require_cmd python3

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  err "not in a git repository"
  exit 2
fi

cd "$ROOT"

ARTICLES_DIR="$ROOT/docs/wiki/articles"
INDEX_FILE="$ROOT/docs/wiki/index.md"
SECTION_CHECK="$ROOT/scripts/wiki/lib/section-context-check.sh"

if [ ! -d "$ARTICLES_DIR" ]; then
  err "$ARTICLES_DIR not found"
  exit 2
fi

if [ -z "$cache_path" ]; then
  cache_path="$ROOT/.cache/wiki-lint.json"
fi
if [ -z "$report_path" ]; then
  report_path="$ROOT/.cache/wiki-lint-report.json"
fi
mkdir -p "$(dirname "$cache_path")" "$(dirname "$report_path")"

# --- Resolve target files ---------------------------------------------------

target_files=()
if [ "${#paths[@]}" -eq 0 ]; then
  while IFS= read -r f; do target_files+=("$f"); done < <(find "$ARTICLES_DIR" -type f -name '*.md' | LC_ALL=C sort)
else
  for p in "${paths[@]}"; do
    if [ -d "$p" ]; then
      while IFS= read -r f; do target_files+=("$f"); done < <(find "$p" -type f -name '*.md' | LC_ALL=C sort)
    elif [ -f "$p" ]; then
      target_files+=("$p")
    else
      err "path not found: $p"
      exit 2
    fi
  done
fi

if [ "${#target_files[@]}" -eq 0 ]; then
  err "no target files"
  exit 0
fi

log "targets=${#target_files[@]} no_llm=$no_llm fix=$do_fix cache=$cache_path legacy_api=$legacy_api"

# --- All articles (for cross-file checks: orphan / broken-link / Related) ---

all_articles=()
while IFS= read -r f; do all_articles+=("$f"); done < <(find "$ARTICLES_DIR" -type f -name '*.md' | LC_ALL=C sort)

# Build slug → relative_path map (slug = basename without .md)
slug_index_tmp=$(mktemp)
for f in "${all_articles[@]}"; do
  rel=${f#"$ROOT"/}
  slug=$(basename "$f" .md)
  printf '%s\t%s\n' "$slug" "$rel" >>"$slug_index_tmp"
done

# Title index is built lazily after parse_cached() is defined (see below).
# slug_lookup() resolves a wikilink target name with B-plan rules:
#   1) slug match (preferred)
#   2) frontmatter.title exact match (fallback)
# Per docs/wiki/SCHEMA.md "### 6. wikilink の解決ルール" (B 案 / KMD-52 cycle 2).
title_index_tmp=$(mktemp)
title_index_built=0

slug_lookup() {
  local name="$1"
  local hit
  # 1) slug match (preferred)
  hit=$(awk -v s="$name" -F'\t' '$1==s{print $2; exit}' "$slug_index_tmp")
  if [ -n "$hit" ]; then
    printf '%s' "$hit"
    return 0
  fi
  # 2) title fallback
  if [ "$title_index_built" -eq 0 ]; then
    build_title_index
  fi
  awk -v s="$name" -F'\t' '$1==s{print $2; exit}' "$title_index_tmp"
}

# --- Frontmatter parsing helper (python) ------------------------------------

# Emit frontmatter as JSON for a file: {title, category, tags, sources, created,
# updated, h1, related, _missing, _line_map}
parse_frontmatter() {
  local f="$1"
  python3 - "$f" <<'PY'
import json, sys, re
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    raw = fh.read()
lines = raw.splitlines()

fm_start = None
fm_end = None
if lines and lines[0].strip() == "---":
    fm_start = 0
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm_end = i
            break

result = {
    "has_frontmatter": fm_start is not None and fm_end is not None,
    "fm_start_line": (fm_start + 1) if fm_start is not None else None,
    "fm_end_line": (fm_end + 1) if fm_end is not None else None,
    "title": None,
    "category": None,
    "tags": [],
    "sources": [],
    "created": None,
    "updated": None,
    "h1": None,
    "related": [],
}

if result["has_frontmatter"]:
    fm_text = "\n".join(lines[fm_start + 1: fm_end])
    # Minimal YAML parser: handle key: scalar, key: [a, b], or key:\n  - a\n  - b
    cur_key = None
    multiline_list_active = False
    fm_lines = fm_text.split("\n")
    parsed = {}
    i = 0
    while i < len(fm_lines):
        line = fm_lines[i]
        if not line.strip():
            i += 1; continue
        if multiline_list_active and re.match(r"^\s*-\s+", line):
            val = re.sub(r"^\s*-\s+", "", line).strip()
            # strip optional surrounding quotes
            if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                val = val[1:-1]
            parsed[cur_key].append(val)
            i += 1; continue
        multiline_list_active = False
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", line)
        if not m:
            i += 1; continue
        k = m.group(1); v = m.group(2)
        if v.strip() == "":
            # multiline list expected
            cur_key = k
            parsed[k] = []
            multiline_list_active = True
            i += 1; continue
        # inline list?
        if v.strip().startswith("[") and v.strip().endswith("]"):
            inner = v.strip()[1:-1].strip()
            if inner == "":
                parsed[k] = []
            else:
                parts = []
                # split on commas not inside quotes
                buf = ""; in_q = None
                for ch in inner:
                    if in_q:
                        if ch == in_q: in_q = None
                        else: buf += ch
                    elif ch in ('"', "'"):
                        in_q = ch
                    elif ch == ",":
                        parts.append(buf.strip()); buf = ""
                    else:
                        buf += ch
                parts.append(buf.strip())
                cleaned = []
                for p in parts:
                    if (p.startswith('"') and p.endswith('"')) or (p.startswith("'") and p.endswith("'")):
                        p = p[1:-1]
                    cleaned.append(p)
                parsed[k] = cleaned
        else:
            val = v.strip()
            if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                val = val[1:-1]
            parsed[k] = val
        i += 1

    for key in ("title", "category", "tags", "sources", "created", "updated"):
        if key in parsed:
            result[key] = parsed[key]

# H1
in_code = False
body_start = (fm_end + 1) if fm_end is not None else 0
for idx in range(body_start, len(lines)):
    line = lines[idx]
    if re.match(r"^\s*```", line):
        in_code = not in_code; continue
    if in_code: continue
    m = re.match(r"^#\s+(.+?)\s*$", line)
    if m:
        result["h1"] = m.group(1).strip()
        break

# Related: lines that start with `- [[...]]` under "## Related"
in_related = False
in_code = False
related = []
for idx in range(body_start, len(lines)):
    line = lines[idx]
    if re.match(r"^\s*```", line):
        in_code = not in_code; continue
    if in_code: continue
    h2 = re.match(r"^##\s+(.+?)\s*$", line)
    if h2:
        in_related = (h2.group(1).strip().lower() == "related")
        continue
    if in_related:
        m = re.match(r"^\s*-\s+\[\[([^\]|]+)(?:\|[^\]]*)?\]\]", line)
        if m:
            related.append(m.group(1).strip())
result["related"] = related

print(json.dumps(result, ensure_ascii=False))
PY
}

# Cache parse results to a temp dir to avoid double-parsing
PARSE_DIR=$(mktemp -d)

parse_cached() {
  local f="$1"
  local key
  key=$(printf '%s' "$f" | shasum -a 256 | awk '{print $1}')
  local cache_file="$PARSE_DIR/$key.json"
  if [ ! -f "$cache_file" ]; then
    parse_frontmatter "$f" >"$cache_file"
  fi
  cat "$cache_file"
}

# --- Title index (B-plan wikilink resolution / SCHEMA §6) -------------------
#
# Build a `frontmatter.title<TAB>relpath` map by parsing each article's
# frontmatter. Used as the fallback resolver inside slug_lookup() when a
# `[[name]]` does not match any slug. Built lazily on first miss.

build_title_index() {
  local f rel parsed title
  for f in "${all_articles[@]}"; do
    rel=${f#"$ROOT"/}
    parsed=$(parse_cached "$f")
    title=$(printf '%s' "$parsed" | jq -r '.title // empty')
    if [ -n "$title" ]; then
      printf '%s\t%s\n' "$title" "$rel" >>"$title_index_tmp"
    fi
  done
  title_index_built=1
}

# --- Pre-compute: all incoming references (slug → list of referrers) --------

# referrers_tmp: slug<TAB>referrer_relpath
referrers_tmp=$(mktemp)

# index.md references
if [ -f "$INDEX_FILE" ]; then
  # Markdown links: (articles/...md)
  grep -oE '\(articles/[^)]+\.md\)' "$INDEX_FILE" 2>/dev/null \
    | sed -E 's#^\(articles/##; s#\.md\)$##' \
    | while IFS= read -r linkpath; do
        # linkpath e.g. components/ai-service → use last segment as slug
        slug=$(basename "$linkpath")
        printf '%s\t%s\n' "$slug" "docs/wiki/index.md"
      done >>"$referrers_tmp"
fi

# Per-article Related references
for f in "${all_articles[@]}"; do
  rel=${f#"$ROOT"/}
  parsed=$(parse_cached "$f")
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '%s\t%s\n' "$r" "$rel" >>"$referrers_tmp"
  done < <(printf '%s' "$parsed" | jq -r '.related[]?')
done

is_referenced() {
  # arg1: slug → exit 0 if referenced anywhere
  awk -v s="$1" -F'\t' '$1==s{found=1; exit} END{exit found?0:1}' "$referrers_tmp"
}

# --- Violation emitter ------------------------------------------------------
#
# Each `emit` call writes the NDJSON line to both stdout (the consumer of
# lint.sh) and an internal log file. Counting lines in the log avoids the
# subshell counter problem (when emit runs inside a `while … | …` pipeline
# the parent's `violation_count` would not be updated).

VIOLATION_LOG=$(mktemp)
PARSE_DIR_BASE="$PARSE_DIR"
trap 'rm -rf "$PARSE_DIR_BASE"; rm -f "$slug_index_tmp" "$title_index_tmp" "$referrers_tmp" "$VIOLATION_LOG"' EXIT

rule_frontmatter_files=0
rule_orphan_files=0
rule_broken_link_files=0
rule_stale_files=0
rule_section_context_attempted=0
rule_section_context_executed=0
rule_section_context_skipped=0
rule_section_context_failed=0
rule_section_context_status="pending"
rule_section_context_reason=""

record_section_context_skip() {
  local reason="$1"
  rule_section_context_skipped=$((rule_section_context_skipped + 1))
  if [ "$rule_section_context_status" = "pending" ]; then
    rule_section_context_status="skipped"
    rule_section_context_reason="$reason"
  fi
}

write_report() {
  jq -nc \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg report_path "$report_path" \
    --argjson target_count "${#target_files[@]}" \
    --argjson violation_count "$violation_count" \
    --argjson no_llm "$no_llm" \
    --argjson legacy_api "$legacy_api" \
    --arg section_status "$rule_section_context_status" \
    --arg section_reason "$rule_section_context_reason" \
    --argjson rule_frontmatter_files "$rule_frontmatter_files" \
    --argjson rule_orphan_files "$rule_orphan_files" \
    --argjson rule_broken_link_files "$rule_broken_link_files" \
    --argjson rule_stale_files "$rule_stale_files" \
    --argjson section_attempted "$rule_section_context_attempted" \
    --argjson section_executed "$rule_section_context_executed" \
    --argjson section_skipped "$rule_section_context_skipped" \
    --argjson section_failed "$rule_section_context_failed" \
    '{
      generated_at: $generated_at,
      report_path: $report_path,
      target_count: $target_count,
      violation_count: $violation_count,
      options: {
        no_llm: ($no_llm == 1),
        legacy_api: ($legacy_api == 1)
      },
      rules: {
        frontmatter: {status: "executed", files: $rule_frontmatter_files},
        orphan: {status: "executed", files: $rule_orphan_files},
        broken_link: {status: "executed", files: $rule_broken_link_files},
        stale: {status: "executed", files: $rule_stale_files},
        section_context: {
          status: $section_status,
          reason: (if $section_reason == "" then null else $section_reason end),
          attempted_files: $section_attempted,
          executed_files: $section_executed,
          skipped_files: $section_skipped,
          failed_files: $section_failed
        }
      },
      rules_executed: (
        ["frontmatter", "orphan", "broken_link", "stale"] +
        (if $section_executed > 0 then ["section_context"] else [] end)
      ),
      rules_skipped: (
        if $section_skipped > 0 then ["section_context"] else [] end
      ),
      rules_failed: (
        if $section_failed > 0 then ["section_context"] else [] end
      )
    }' >"$report_path"
}

emit() {
  local file="$1" rule="$2" line="$3" detail="$4" model_tag="${5:-shell}"
  local line_arg
  if [ "$line" = "null" ] || [ -z "$line" ]; then
    line_arg="null"
  else
    line_arg="$line"
  fi
  local rec
  rec=$(jq -nc \
    --arg file "$file" \
    --arg rule "$rule" \
    --argjson line "$line_arg" \
    --arg detail "$detail" \
    --arg model "$model_tag" \
    '{file:$file, rule:$rule, line:$line, detail:$detail, model:$model}')
  printf '%s\n' "$rec"
  printf '%s\n' "$rec" >>"$VIOLATION_LOG"
}

# --- Rule 5: frontmatter ----------------------------------------------------

VALID_CATEGORIES_RE='^(architecture|concepts|decisions|components|practices)$'
TAG_RE='^[a-z0-9]+(-[a-z0-9]+)*$'

check_frontmatter() {
  local f="$1"
  rule_frontmatter_files=$((rule_frontmatter_files + 1))
  local rel=${f#"$ROOT"/}
  local parsed
  parsed=$(parse_cached "$f")

  local has_fm
  has_fm=$(printf '%s' "$parsed" | jq -r '.has_frontmatter')
  if [ "$has_fm" != "true" ]; then
    emit "$rel" "frontmatter-missing" 1 "frontmatter block (---) not found at top of file"
    return
  fi

  # Required fields
  local title category tags_count sources_set created updated h1
  title=$(printf '%s' "$parsed" | jq -r '.title // ""')
  category=$(printf '%s' "$parsed" | jq -r '.category // ""')
  tags_count=$(printf '%s' "$parsed" | jq -r '.tags | length')
  sources_set=$(printf '%s' "$parsed" | jq -r 'has("sources")')
  created=$(printf '%s' "$parsed" | jq -r '.created // ""')
  updated=$(printf '%s' "$parsed" | jq -r '.updated // ""')
  h1=$(printf '%s' "$parsed" | jq -r '.h1 // ""')

  if [ -z "$title" ]; then
    emit "$rel" "frontmatter-required-field-missing" null "required field missing: title"
  fi
  if [ -z "$category" ]; then
    emit "$rel" "frontmatter-required-field-missing" null "required field missing: category"
  else
    if ! printf '%s' "$category" | grep -Eq "$VALID_CATEGORIES_RE"; then
      emit "$rel" "frontmatter-invalid-category" null "invalid category '$category' (must be one of architecture/concepts/decisions/components/practices)"
    else
      # Path consistency: articles/<category>/...
      local expected_prefix="docs/wiki/articles/${category}/"
      case "$rel" in
        "$expected_prefix"*) : ;;
        *) emit "$rel" "frontmatter-category-path-mismatch" null "category=$category but file is under ${rel#docs/wiki/articles/}" ;;
      esac
    fi
  fi
  if [ "$tags_count" = "0" ] || [ -z "$tags_count" ]; then
    emit "$rel" "frontmatter-required-field-missing" null "required field missing or empty: tags (need >=1)"
  else
    # Tag naming convention
    while IFS= read -r tag; do
      [ -n "$tag" ] || continue
      if ! printf '%s' "$tag" | grep -Eq "$TAG_RE"; then
        emit "$rel" "frontmatter-tag-naming" null "tag '$tag' violates lowercase-kebab convention"
      fi
      if [ "${#tag}" -gt 30 ]; then
        emit "$rel" "frontmatter-tag-too-long" null "tag '$tag' exceeds 30 characters"
      fi
    done < <(printf '%s' "$parsed" | jq -r '.tags[]?')
  fi
  if [ "$sources_set" != "true" ]; then
    emit "$rel" "frontmatter-required-field-missing" null "required field missing: sources (use [] if none)"
  fi
  if [ -z "$created" ]; then
    emit "$rel" "frontmatter-required-field-missing" null "required field missing: created"
  elif ! printf '%s' "$created" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    emit "$rel" "frontmatter-invalid-date" null "created='$created' is not ISO 8601 (YYYY-MM-DD)"
  fi
  if [ -z "$updated" ]; then
    emit "$rel" "frontmatter-required-field-missing" null "required field missing: updated"
  elif ! printf '%s' "$updated" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    emit "$rel" "frontmatter-invalid-date" null "updated='$updated' is not ISO 8601 (YYYY-MM-DD)"
  elif [ -n "$created" ] && [ "$updated" \< "$created" ]; then
    emit "$rel" "frontmatter-updated-before-created" null "updated=$updated is earlier than created=$created"
  fi

  # H1 vs title
  if [ -n "$title" ] && [ -n "$h1" ] && [ "$title" != "$h1" ]; then
    emit "$rel" "frontmatter-title-h1-mismatch" null "title='$title' does not match H1='$h1'"
  fi

  # Related symmetry: for each [[slug]] in this file's Related, ensure target
  # exists and has this article (by slug) in its Related.
  local self_slug
  self_slug=$(basename "$f" .md)
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    target=$(slug_lookup "$r")
    if [ -z "$target" ]; then
      # broken link case is handled by rule 2; do not emit here
      continue
    fi
    target_parsed=$(parse_cached "$ROOT/$target")
    has_back=$(printf '%s' "$target_parsed" | jq -r --arg s "$self_slug" '.related | index($s) // empty')
    if [ -z "$has_back" ]; then
      emit "$rel" "related-asymmetric" null "Related links to [[${r}]] but ${target} does not link back to [[${self_slug}]]"
    fi
  done < <(printf '%s' "$parsed" | jq -r '.related[]?')
}

# --- Rule 1: orphan ---------------------------------------------------------

check_orphan() {
  local f="$1"
  rule_orphan_files=$((rule_orphan_files + 1))
  local rel=${f#"$ROOT"/}
  local slug
  slug=$(basename "$f" .md)
  if ! is_referenced "$slug"; then
    emit "$rel" "orphan" null "no incoming reference from index.md or any other article's Related"
  fi
}

# --- Rule 2: broken-link ----------------------------------------------------
#
# Scan the whole article body for [[wikilink]] occurrences (not just Related)
# and ensure each target slug resolves to an article file.

check_broken_links() {
  local f="$1"
  rule_broken_link_files=$((rule_broken_link_files + 1))
  local rel=${f#"$ROOT"/}

  # Extract [[slug]] outside of code fences with line numbers
  python3 - "$f" <<'PY' | while IFS=$'\t' read -r line slug; do
import sys, re
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    raw = fh.read()
lines = raw.splitlines()
in_code = False
for i, line in enumerate(lines, 1):
    if re.match(r"^\s*```", line):
        in_code = not in_code; continue
    if in_code: continue
    # Remove inline-code spans before searching for [[...]]
    stripped = re.sub(r"`[^`]*`", "", line)
    for m in re.finditer(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]", stripped):
        slug = m.group(1).strip()
        # Skip things that look like URLs or paths
        if "/" in slug or slug.startswith("http"):
            continue
        print(f"{i}\t{slug}")
PY
    target=$(slug_lookup "$slug")
    if [ -z "$target" ]; then
      emit "$rel" "broken-link" "$line" "[[${slug}]] does not resolve to any article"
    fi
  done
}

# --- Rule 3: stale ----------------------------------------------------------
#
# `updated` older than 60 days AND any `sources` file has a newer mtime than
# `updated` → flag as stale.

today_epoch=$(date +%s)

check_stale() {
  local f="$1"
  rule_stale_files=$((rule_stale_files + 1))
  local rel=${f#"$ROOT"/}
  local parsed
  parsed=$(parse_cached "$f")

  local updated
  updated=$(printf '%s' "$parsed" | jq -r '.updated // ""')
  if [ -z "$updated" ] || ! printf '%s' "$updated" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    return
  fi

  local upd_epoch
  if ! upd_epoch=$(date -j -f "%Y-%m-%d" "$updated" "+%s" 2>/dev/null); then
    return
  fi

  local age_days
  age_days=$(( (today_epoch - upd_epoch) / 86400 ))
  if [ "$age_days" -lt 60 ]; then
    return
  fi

  # Check sources mtime drift
  local newer_sources=()
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    local src_path="$ROOT/$src"
    if [ ! -f "$src_path" ]; then
      continue
    fi
    local src_epoch
    src_epoch=$(stat -f %m "$src_path" 2>/dev/null || echo 0)
    if [ "$src_epoch" -gt "$upd_epoch" ]; then
      newer_sources+=("$src")
    fi
  done < <(printf '%s' "$parsed" | jq -r '.sources[]?')

  if [ "${#newer_sources[@]}" -gt 0 ]; then
    local list
    list=$(printf '%s,' "${newer_sources[@]}" | sed 's/,$//')
    emit "$rel" "stale" null "updated=$updated is ${age_days}d old AND newer sources detected: $list"
  fi
}

# --- Rule 4: section-context-missing (Haiku) --------------------------------

check_section_context() {
  local f="$1"
  rule_section_context_attempted=$((rule_section_context_attempted + 1))
  if [ "$no_llm" -eq 1 ]; then
    record_section_context_skip "no_llm"
    return
  fi
  if [ ! -x "$SECTION_CHECK" ]; then
    err "WARN: $SECTION_CHECK not executable; skipping rule 4"
    record_section_context_skip "helper_not_executable"
    return
  fi
  # The helper emits NDJSON to stdout; we forward and count.
  local tmp
  tmp=$(mktemp)
  local rc=0
  local extra_args=()
  if [ "$legacy_api" -eq 1 ]; then
    extra_args+=(--legacy-api)
  fi
  "$SECTION_CHECK" \
    --file "$f" \
    --cache "$cache_path" \
    --model "$model" \
    --retries "$retries" \
    ${extra_args[@]+"${extra_args[@]}"} >"$tmp" 2>>/dev/stderr || rc=$?
  if [ "$rc" -ne 0 ]; then
    err "WARN: section-context-check failed (rc=$rc) for $f — skipping that rule"
    rule_section_context_failed=$((rule_section_context_failed + 1))
    rule_section_context_status="failed"
    rule_section_context_reason="helper_failed"
    rm -f "$tmp"
    return
  fi
  rule_section_context_executed=$((rule_section_context_executed + 1))
  rule_section_context_status="executed"
  rule_section_context_reason=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$line"
    printf '%s\n' "$line" >>"$VIOLATION_LOG"
  done <"$tmp"
  rm -f "$tmp"
}

# --- --fix mode -------------------------------------------------------------

apply_fixes() {
  local f="$1"
  python3 - "$f" <<'PY'
import sys, re, datetime
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    raw = fh.read()
lines = raw.splitlines(keepends=False)

if not lines or lines[0].strip() != "---":
    # No frontmatter; insert a minimal one
    today = datetime.date.today().isoformat()
    slug = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    h1 = ""
    in_code = False
    for line in lines:
        if re.match(r"^\s*```", line):
            in_code = not in_code; continue
        if in_code: continue
        m = re.match(r"^#\s+(.+?)\s*$", line)
        if m:
            h1 = m.group(1).strip(); break
    if not h1:
        h1 = slug
    # Guess category from path
    cat = "components"
    m = re.search(r"/articles/([^/]+)/", path)
    if m and m.group(1) in ("architecture","concepts","decisions","components","practices"):
        cat = m.group(1)
    fm = [
        "---",
        f"title: {h1}",
        f"category: {cat}",
        "tags: [TODO]",
        "sources: []",
        f"created: {today}",
        f"updated: {today}",
        "---",
        "",
    ]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(fm + lines) + ("\n" if not raw.endswith("\n") else ""))
    print(f"FIX: inserted frontmatter for {path}")
    sys.exit(0)

# Find frontmatter range
fm_end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        fm_end = i; break
if fm_end is None:
    sys.exit(0)

fm = lines[1:fm_end]
body = lines[fm_end+1:]

def normalize_tag(t: str) -> str:
    s = t.strip().strip('"').strip("'")
    s = re.sub(r"[_\s]+", "-", s).lower()
    s = re.sub(r"[^a-z0-9-]+", "", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s

# Mutate fm
new_fm = []
seen_keys = set()
i = 0
in_list_key = None
list_buf = []

def flush_list():
    global list_buf, in_list_key
    if in_list_key is None:
        return
    if in_list_key == "tags":
        normalized = []
        for t in list_buf:
            n = normalize_tag(t)
            if n and n not in normalized:
                normalized.append(n)
        new_fm.append(f"{in_list_key}: [{', '.join(normalized)}]")
    else:
        if not list_buf:
            new_fm.append(f"{in_list_key}: []")
        else:
            new_fm.append(f"{in_list_key}:")
            for v in list_buf:
                new_fm.append(f"  - {v}")
    in_list_key = None
    list_buf = []

while i < len(fm):
    line = fm[i]
    if in_list_key is not None and re.match(r"^\s*-\s+", line):
        v = re.sub(r"^\s*-\s+", "", line).strip()
        list_buf.append(v.strip('"').strip("'"))
        i += 1; continue
    if in_list_key is not None:
        flush_list()
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", line)
    if not m:
        new_fm.append(line); i += 1; continue
    k = m.group(1); v = m.group(2)
    seen_keys.add(k)
    if k == "tags":
        if v.strip() == "":
            in_list_key = "tags"
            list_buf = []
            i += 1; continue
        if v.strip().startswith("[") and v.strip().endswith("]"):
            inner = v.strip()[1:-1].strip()
            parts = []
            buf = ""; in_q = None
            for ch in inner:
                if in_q:
                    if ch == in_q: in_q = None
                    else: buf += ch
                elif ch in ('"', "'"):
                    in_q = ch
                elif ch == ",":
                    parts.append(buf.strip()); buf = ""
                else:
                    buf += ch
            if inner != "":
                parts.append(buf.strip())
            normalized = []
            for p in parts:
                if (p.startswith('"') and p.endswith('"')) or (p.startswith("'") and p.endswith("'")):
                    p = p[1:-1]
                n = normalize_tag(p)
                if n and n not in normalized:
                    normalized.append(n)
            new_fm.append(f"tags: [{', '.join(normalized)}]")
            i += 1; continue
        # scalar tags? treat as single-tag list
        n = normalize_tag(v)
        new_fm.append(f"tags: [{n}]" if n else "tags: []")
        i += 1; continue
    new_fm.append(line); i += 1

if in_list_key is not None:
    flush_list()

# Add missing required fields
today = datetime.date.today().isoformat()
required_defaults = {
    "title": "TODO",
    "category": "components",
    "tags": "tags: [TODO]",
    "sources": "sources: []",
    "created": f"created: {today}",
    "updated": f"updated: {today}",
}
appended = []
for k, default in required_defaults.items():
    if k not in seen_keys:
        if k in ("tags", "sources", "created", "updated"):
            appended.append(default)
        else:
            appended.append(f"{k}: {default}")

if appended:
    new_fm.extend(appended)

if new_fm == fm:
    sys.exit(0)

out_lines = ["---"] + new_fm + ["---"] + body
with open(path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out_lines) + ("\n" if not raw.endswith("\n") else ""))
print(f"FIX: normalized frontmatter in {path}")
PY
}

# --- Main loop --------------------------------------------------------------

if [ "$do_fix" -eq 1 ]; then
  log "applying --fix to ${#target_files[@]} files"
  for f in "${target_files[@]}"; do
    apply_fixes "$f"
  done
  # Drop parse cache so re-parsing reflects fixes
  rm -f "$PARSE_DIR"/*.json 2>/dev/null || true
fi

for f in "${target_files[@]}"; do
  check_frontmatter "$f"
  check_orphan "$f"
  check_broken_links "$f"
  check_stale "$f"
  check_section_context "$f"
done

violation_count=$(wc -l <"$VIOLATION_LOG" | awk '{print $1}')
if [ "$rule_section_context_status" = "pending" ]; then
  rule_section_context_status="skipped"
  rule_section_context_reason="not_requested"
fi
write_report
log "done: violations=$violation_count"

if [ "$violation_count" -gt 0 ]; then
  exit 1
fi
exit 0
