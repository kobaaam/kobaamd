#!/usr/bin/env bash
set -euo pipefail

# scripts/wiki/lib/section-context-check.sh
#
# 単一の wiki 記事ファイルを受け取り、各 H3 セクション（と H2 セクション）が
# 「セクション単独で文脈を成すか」を Anthropic Haiku に判定させる。
#
# - Prompt Caching: 記事全体を system 側 static block に置き、cache_control:ephemeral
#   を付与する。同じ記事内の複数セクション判定では cache_read が増えるはず
# - リトライ: 3 回（指数バックオフ 2/4/8 秒）。最終失敗はそのセクションをスキップ
#   して警告ログを出し、ファイル全体としては exit 0 を返す（呼び出し元の lint.sh が
#   止まらないようにするため）
# - content_hash キャッシュ: --cache <path> で JSON ファイルを指定すると、
#   sha256(record) → "YES"|"NO|<reason>" を保存・参照
#
# Usage:
#   section-context-check.sh \
#     --file docs/wiki/articles/components/ai-service.md \
#     [--cache .cache/wiki-lint.json] \
#     [--model claude-haiku-4-5] \
#     [--retries 3]
#
# Output (stdout): NDJSON, 1 行 = 1 違反のみ（合格セクションは出力しない）
#   {"file":"...","rule":"section-context-missing","line":42,
#    "detail":"...","model":"haiku","section_id":"..."}
#
# Stderr:
#   - 開始時に対象ファイル / セクション数 / cache_control 設定をログ出力
#   - 各 API 呼び出し後に usage（cache_create / cache_read）を出力
#   - 失敗時は警告のみ（処理は継続）

err() { printf 'section-context-check: %s\n' "$*" >&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 1
  fi
}

usage() {
  cat <<'EOF' >&2
Usage: section-context-check.sh --file <path> [options]

Options:
  --file <path>     Path to wiki article (required)
  --cache <path>    JSON cache file for content_hash → verdict (optional)
  --model <id>      Anthropic model id (default: claude-haiku-4-5)
  --retries <n>     Retry attempts (default: 3)
  --base-url <url>  Override Anthropic base URL
  --dry-run         Print prompts that would be sent, do not call API
  -h, --help        Show this help and exit
EOF
}

file_path=""
cache_path=""
model="${ANTHROPIC_HAIKU_MODEL:-claude-haiku-4-5}"
retries=3
base_url="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --file)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      file_path="$2"; shift 2 ;;
    --cache)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      cache_path="$2"; shift 2 ;;
    --model)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      model="$2"; shift 2 ;;
    --retries)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      retries="$2"; shift 2 ;;
    --base-url)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      base_url="$2"; shift 2 ;;
    --dry-run)
      dry_run=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "unknown argument: $1"; usage; exit 2 ;;
  esac
done

if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
  err "missing or non-existent --file: $file_path"
  exit 2
fi

if [ "$dry_run" -ne 1 ]; then
  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    err "ANTHROPIC_API_KEY is not set (try: source ~/.zshrc)"
    exit 1
  fi
  require_cmd curl
fi

require_cmd jq
require_cmd python3
require_cmd shasum

# --- Helpers ----------------------------------------------------------------

content_hash() {
  # arg1: text → sha256 hex
  printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
}

cache_lookup() {
  # arg1: hash → echo verdict ("YES" or "NO|reason") if hit, empty otherwise
  local h="$1"
  if [ -z "$cache_path" ] || [ ! -f "$cache_path" ]; then
    return 0
  fi
  jq -r --arg h "$h" '.section_context[$h] // empty' "$cache_path" 2>/dev/null || true
}

cache_store() {
  # arg1: hash, arg2: verdict
  local h="$1" v="$2"
  [ -n "$cache_path" ] || return 0
  mkdir -p "$(dirname "$cache_path")"
  if [ ! -f "$cache_path" ]; then
    printf '%s' '{"section_context":{},"version":1}' >"$cache_path"
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg h "$h" --arg v "$v" \
    '.section_context[$h] = $v | .version = (.version // 1)' \
    "$cache_path" >"$tmp" && mv "$tmp" "$cache_path"
}

# --- Section extraction (python helper) -------------------------------------
#
# Why python: shell-only H2/H3 extraction with line numbers and code-fence
# awareness gets gnarly. python3 is available on every macOS host.
#
# We write the python source to a temp file rather than embedding it inside a
# command substitution, because command substitution `$(...)` re-interprets
# backticks inside the heredoc (the regex `^\s*` followed by triple backticks
# would be parsed as backtick command substitution).

py_extract=$(mktemp)
trap 'rm -f "$py_extract"' EXIT
cat >"$py_extract" <<'PY'
import json, sys, re
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    raw = f.read()
lines = raw.splitlines()

# Detect frontmatter to skip
fm_end = 0
if lines and lines[0].strip() == "---":
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm_end = i + 1
            break

sections = []  # list of {level, title, line, body}
in_code = False
FENCE = "```"
header_re = re.compile(r"^(#{2,3})\s+(.+?)\s*$")

current = None  # (level, title, line, [body_lines])

def flush():
    if current is None:
        return
    lvl, title, line_no, body = current
    sections.append({
        "level": lvl,
        "title": title,
        "line": line_no,
        "body": "\n".join(body).rstrip(),
    })

for idx in range(fm_end, len(lines)):
    line = lines[idx]
    if line.lstrip().startswith(FENCE):
        in_code = not in_code
        if current is not None:
            current[3].append(line)
        continue
    if not in_code:
        m = header_re.match(line)
        if m:
            flush()
            level = len(m.group(1))
            title = m.group(2).strip()
            current = (level, title, idx + 1, [])
            continue
    if current is not None:
        current[3].append(line)

flush()

# Filter out level 1 / Summary-only / Related / Sources sections
ignored_titles = {"Summary", "Related", "Sources", "Content"}
out = []
for s in sections:
    if s["title"] in ignored_titles:
        continue
    # If body is essentially empty after stripping, skip
    if not s["body"].strip():
        continue
    out.append(s)

print(json.dumps({"sections": out}, ensure_ascii=False))
PY

sections_json=$(python3 "$py_extract" "$file_path")

section_count=$(printf '%s' "$sections_json" | jq -r '.sections | length')

err "file=$file_path sections=$section_count cache_control=ephemeral model=$model"

if [ "$section_count" -eq 0 ]; then
  exit 0
fi

# --- Build the cached system block once per file ----------------------------
# Per Anthropic Prompt Caching: identical system prefix → cache hit. We send
# the full article body as the cached static block; user turn carries the
# section-specific question.

article_body=$(cat "$file_path")
relative_path=${file_path}

system_preamble='You are a documentation reviewer for the kobaamd LLM Wiki. The system block contains the full text of one wiki article. The user will quote one of its H2/H3 sections and ask whether that section, read in isolation (without the article title or surrounding context), conveys clearly what topic it covers. Reply with one of: "YES" or "NO: <one-line reason>". Do not add any other commentary.'

# --- Per-section loop -------------------------------------------------------

i=0
violations=0
while [ "$i" -lt "$section_count" ]; do
  section=$(printf '%s' "$sections_json" | jq -c ".sections[$i]")
  level=$(printf '%s' "$section" | jq -r '.level')
  title=$(printf '%s' "$section" | jq -r '.title')
  line=$(printf '%s' "$section" | jq -r '.line')
  body=$(printf '%s' "$section" | jq -r '.body')

  # Compute a stable hash including the article path to avoid cross-file collisions
  hash_input="${relative_path}|H${level}|${title}|${body}"
  h=$(content_hash "$hash_input")

  cached=""
  if [ -n "$cache_path" ]; then
    cached=$(cache_lookup "$h")
  fi

  verdict=""
  if [ -n "$cached" ]; then
    verdict="$cached"
  else
    section_quote="$(printf '## (H%s) %s\n\n%s' "$level" "$title" "$body")"

    # Build payload
    payload_tmp=$(mktemp)
    response_tmp=$(mktemp)
    http_tmp=$(mktemp)

    jq -n \
      --arg model "$model" \
      --arg preamble "$system_preamble" \
      --arg article "$article_body" \
      --arg path "$relative_path" \
      --arg sec "$section_quote" \
      '{
        model: $model,
        max_tokens: 256,
        system: [
          { type: "text", text: $preamble },
          {
            type: "text",
            text: ("# Article: " + $path + "\n\n" + $article),
            cache_control: { type: "ephemeral" }
          }
        ],
        messages: [
          { role: "user",
            content: ("Question: read the following section in isolation. Without the article title or surrounding context, can a reader understand what topic this section covers? Answer YES or with a one-line reason starting with NO:.\n\n---\n" + $sec + "\n---") }
        ]
      }' >"$payload_tmp"

    if [ "$dry_run" -eq 1 ]; then
      err "[dry-run] would POST: $relative_path :: H${level} ${title}"
      rm -f "$payload_tmp" "$response_tmp" "$http_tmp"
      i=$((i + 1))
      continue
    fi

    attempt=0
    success=0
    while [ "$attempt" -lt "$retries" ]; do
      attempt=$((attempt + 1))
      : >"$response_tmp"
      : >"$http_tmp"

      set +e
      curl --silent --show-error --fail-with-body \
        --max-time 90 \
        --output "$response_tmp" \
        --write-out '%{http_code}' \
        -X POST "$base_url/v1/messages" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H 'anthropic-version: 2023-06-01' \
        -H 'content-type: application/json' \
        --data-binary "@$payload_tmp" \
        >"$http_tmp"
      curl_exit=$?
      set -e

      http_code=$(cat "$http_tmp" 2>/dev/null || echo "")

      if [ "$curl_exit" -eq 0 ] && [ "$http_code" = "200" ]; then
        success=1
        break
      fi

      err "attempt ${attempt}/${retries} failed (curl=${curl_exit} http=${http_code:-?}) section='${title}'"
      if [ -s "$response_tmp" ]; then
        head -c 1024 "$response_tmp" >&2 || true
        printf '\n' >&2
      fi
      if [ "$attempt" -lt "$retries" ]; then
        sleep_for=$((1 << attempt))
        sleep "$sleep_for"
      fi
    done

    if [ "$success" -ne 1 ]; then
      err "WARN: skipping section '${title}' (file=$relative_path) — all retries failed"
      rm -f "$payload_tmp" "$response_tmp" "$http_tmp"
      i=$((i + 1))
      continue
    fi

    # Surface usage to stderr (cache observability)
    jq -r --arg t "$title" '
      .usage // {} | "haiku usage: input=\(.input_tokens // 0) output=\(.output_tokens // 0) cache_create=\(.cache_creation_input_tokens // 0) cache_read=\(.cache_read_input_tokens // 0) section=\($t)"
    ' "$response_tmp" >&2 || true

    answer=$(jq -r '
      if (.content | type) == "array" then
        [ .content[] | select(.type == "text") | .text ] | join("")
      else "" end
    ' "$response_tmp")

    rm -f "$payload_tmp" "$response_tmp" "$http_tmp"

    # Normalize: keep first non-empty line, trim
    verdict=$(printf '%s' "$answer" | awk 'NF{print; exit}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -z "$verdict" ]; then
      err "WARN: empty verdict for section '${title}' (file=$relative_path) — skipping"
      i=$((i + 1))
      continue
    fi

    cache_store "$h" "$verdict"
  fi

  # Interpret verdict
  case "$verdict" in
    YES*|yes*|Yes*)
      :
      ;;
    NO*|no*|No*)
      reason=$(printf '%s' "$verdict" | sed -E 's/^[Nn][Oo][:：]?[[:space:]]*//')
      detail="H${level} '${title}': ${reason}"
      jq -nc \
        --arg file "$relative_path" \
        --arg rule "section-context-missing" \
        --argjson line "$line" \
        --arg detail "$detail" \
        --arg model "haiku" \
        --arg section_id "H${level}/${title}" \
        '{file:$file, rule:$rule, line:$line, detail:$detail, model:$model, section_id:$section_id}'
      violations=$((violations + 1))
      ;;
    *)
      err "WARN: unparseable verdict for '${title}': ${verdict}"
      ;;
  esac

  i=$((i + 1))
done

err "section-context-check: file=$relative_path sections=$section_count violations=$violations"
exit 0
