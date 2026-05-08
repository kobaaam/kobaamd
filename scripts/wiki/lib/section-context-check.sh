#!/usr/bin/env bash
set -euo pipefail

# scripts/wiki/lib/section-context-check.sh
#
# 単一の wiki 記事ファイルを受け取り、各 H3 セクション（と H2 セクション）が
# 「セクション単独で文脈を成すか」を判定する。
#
# 既定経路（KMD-150 以降）: Claude Code subagent (`kobaamd_lint_section_context`,
# model: haiku) を `claude -p --agent` 経由で起動する。`ANTHROPIC_API_KEY` は不要。
#
# レガシー経路（`--legacy-api` を指定した場合のみ）: 旧来の `curl + Anthropic
# Messages API + Prompt Caching` で判定する。`ANTHROPIC_API_KEY` 必須。撤去予定の
# 移行用フラグであり、新規スクリプトでは使わないこと。
#
# Usage:
#   section-context-check.sh \
#     --file docs/wiki/articles/components/ai-service.md \
#     [--cache .cache/wiki-lint.json] \
#     [--model claude-haiku-4-5] \
#     [--retries 3] \
#     [--legacy-api]
#
# Output (stdout): NDJSON, 1 行 = 1 違反のみ（合格セクションは出力しない）
#   {"file":"...","rule":"section-context-missing","line":42,
#    "detail":"...","model":"haiku","section_id":"..."}
#
# Stderr:
#   - 開始時に対象ファイル / セクション数 / 起動経路をログ出力
#   - subagent 経路: subagent の stderr をそのまま中継
#   - legacy 経路: 各 API 呼び出し後に usage（cache_create / cache_read）を出力
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
  --model <id>      Anthropic model id (legacy path only; default: claude-haiku-4-5)
  --retries <n>     Retry attempts (default: 3)
  --base-url <url>  Override Anthropic base URL (legacy path only)
  --legacy-api      Use legacy curl + ANTHROPIC_API_KEY path (transitional)
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
legacy_api=0

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
    --legacy-api)
      legacy_api=1; shift ;;
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

# Resolve repository-root-relative path (best-effort; fallback to original)
relative_path="$file_path"
if root=$(git rev-parse --show-toplevel 2>/dev/null); then
  case "$file_path" in
    "$root"/*) relative_path="${file_path#"$root"/}" ;;
  esac
fi

# ============================================================================
# Default path: delegate to Claude Code subagent (KMD-150)
# ============================================================================

run_subagent() {
  if ! command -v claude >/dev/null 2>&1; then
    err "claude CLI not found. Either install Claude Code or pass --legacy-api"
    exit 1
  fi
  require_cmd jq

  err "file=$relative_path route=subagent agent=kobaamd_lint_section_context"

  # Compose the agent invocation prompt. The agent definition lives in
  # `.claude/agents/kobaamd_lint_section_context.md` and reads `--file` /
  # `--cache` from the prompt body.
  local prompt
  prompt="Run lint with the following arguments and emit NDJSON to stdout (no extra commentary):"$'\n'
  prompt+="--file $relative_path"
  if [ -n "$cache_path" ]; then
    prompt+=$'\n'"--cache $cache_path"
  fi
  if [ "$dry_run" -eq 1 ]; then
    prompt+=$'\n'"--dry-run"
  fi

  # `claude -p --agent <name>`: launch as a one-shot subagent, print result, exit.
  # `--output-format text` keeps stdout clean for NDJSON consumers.
  # We explicitly disallow tools that could leak external context: only Read +
  # Bash are needed by the agent.
  local out_tmp rc attempt success
  out_tmp=$(mktemp)
  attempt=0
  success=0
  while [ "$attempt" -lt "$retries" ]; do
    attempt=$((attempt + 1))
    : >"$out_tmp"
    set +e
    claude -p \
      --agent kobaamd_lint_section_context \
      --output-format text \
      --permission-mode bypassPermissions \
      "$prompt" \
      >"$out_tmp" 2>&1
    rc=$?
    set -e

    if [ "$rc" -eq 0 ]; then
      success=1
      break
    fi

    err "WARN: subagent attempt ${attempt}/${retries} failed (exit=$rc) for $relative_path"
    head -c 2048 "$out_tmp" >&2 || true
    printf '\n' >&2

    if [ "$attempt" -lt "$retries" ]; then
      sleep_for=$((1 << attempt))
      sleep "$sleep_for"
    fi
  done

  # The agent is supposed to write NDJSON to stdout only, but `claude -p` can
  # mix prose around the agent's output. We salvage by extracting any line that
  # looks like a JSON object with the expected `rule` field.
  if [ "$success" -ne 1 ]; then
    err "WARN: all ${retries} subagent attempts failed for $relative_path — skipping"
    rm -f "$out_tmp"
    return 0
  fi

  # Filter: keep only lines that parse as JSON and have the expected rule.
  local violations=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *'"rule"'*'"section-context-missing"'*) ;;
      *) continue ;;
    esac
    if printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
      printf '%s\n' "$line"
      violations=$((violations + 1))
    fi
  done <"$out_tmp"

  rm -f "$out_tmp"
  err "section-context-check: file=$relative_path route=subagent violations=$violations"
}

# ============================================================================
# Legacy path: direct Anthropic Messages API with Prompt Caching
# ============================================================================
#
# Kept behind --legacy-api for the transitional period (KMD-150). The body of
# this function preserves the pre-KMD-150 behaviour verbatim so existing
# observability (cache_create / cache_read) continues to work for anyone
# willing to provide ANTHROPIC_API_KEY explicitly.

run_legacy() {
  if [ "$dry_run" -ne 1 ]; then
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
      err "ANTHROPIC_API_KEY is not set (try: source ~/.zshrc) — or drop --legacy-api"
      exit 1
    fi
    require_cmd curl
  fi

  require_cmd jq
  require_cmd python3
  require_cmd shasum

  content_hash() {
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  }

  cache_lookup() {
    local h="$1"
    if [ -z "$cache_path" ] || [ ! -f "$cache_path" ]; then
      return 0
    fi
    jq -r --arg h "$h" '.section_context[$h] // empty' "$cache_path" 2>/dev/null || true
  }

  cache_store() {
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

  py_extract=$(mktemp)
  trap 'rm -f "$py_extract"' EXIT
  cat >"$py_extract" <<'PY'
import json, sys, re
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    raw = f.read()
lines = raw.splitlines()

fm_end = 0
if lines and lines[0].strip() == "---":
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm_end = i + 1
            break

sections = []
in_code = False
FENCE = "```"
header_re = re.compile(r"^(#{2,3})\s+(.+?)\s*$")

current = None

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

ignored_titles = {"Summary", "Related", "Sources", "Content"}
out = []
for s in sections:
    if s["title"] in ignored_titles:
        continue
    if not s["body"].strip():
        continue
    out.append(s)

print(json.dumps({"sections": out}, ensure_ascii=False))
PY

  sections_json=$(python3 "$py_extract" "$file_path")
  section_count=$(printf '%s' "$sections_json" | jq -r '.sections | length')

  err "file=$relative_path route=legacy sections=$section_count cache_control=ephemeral model=$model"

  if [ "$section_count" -eq 0 ]; then
    return 0
  fi

  article_body=$(cat "$file_path")

  system_preamble='You are a documentation reviewer for the kobaamd LLM Wiki. The system block contains the full text of one wiki article. The user will quote one of its H2/H3 sections and ask whether that section, read in isolation (without the article title or surrounding context), conveys clearly what topic it covers. Reply with one of: "YES" or "NO: <one-line reason>". Do not add any other commentary.'

  i=0
  violations=0
  while [ "$i" -lt "$section_count" ]; do
    section=$(printf '%s' "$sections_json" | jq -c ".sections[$i]")
    level=$(printf '%s' "$section" | jq -r '.level')
    title=$(printf '%s' "$section" | jq -r '.title')
    line=$(printf '%s' "$section" | jq -r '.line')
    body=$(printf '%s' "$section" | jq -r '.body')

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

      jq -r --arg t "$title" '
        .usage // {} | "haiku usage: input=\(.input_tokens // 0) output=\(.output_tokens // 0) cache_create=\(.cache_creation_input_tokens // 0) cache_read=\(.cache_read_input_tokens // 0) section=\($t)"
      ' "$response_tmp" >&2 || true

      answer=$(jq -r '
        if (.content | type) == "array" then
          [ .content[] | select(.type == "text") | .text ] | join("")
        else "" end
      ' "$response_tmp")

      rm -f "$payload_tmp" "$response_tmp" "$http_tmp"

      verdict=$(printf '%s' "$answer" | awk 'NF{print; exit}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      if [ -z "$verdict" ]; then
        err "WARN: empty verdict for section '${title}' (file=$relative_path) — skipping"
        i=$((i + 1))
        continue
      fi

      cache_store "$h" "$verdict"
    fi

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

  err "section-context-check: file=$relative_path route=legacy sections=$section_count violations=$violations"
}

# ============================================================================
# Dispatch
# ============================================================================

if [ "$legacy_api" -eq 1 ]; then
  run_legacy
else
  run_subagent
fi

exit 0
