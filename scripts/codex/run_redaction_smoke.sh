#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

RUN_LOG_CAPTURE="$TMPDIR/codex_runs.jsonl"
ISSUE_BODY_CAPTURE="$TMPDIR/issue_body.md"

cat >"$TMPDIR/fake_lq.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

CAPTURE="$ISSUE_BODY_CAPTURE"

op="\${1:-}"
shift || true

case "\$op" in
  issue.list)
    printf '[]\n'
    ;;
  issue.create)
    body=""
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        --body)
          body="\$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [ -n "\$body" ] && [ "\${body#@}" != "\$body" ]; then
      cp "\${body#@}" "\$CAPTURE"
    fi
    printf '{"identifier":"KMD-999"}\n'
    ;;
  *)
    printf 'unsupported op: %s\n' "\$op" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$TMPDIR/fake_lq.sh"

source "$ROOT_DIR/scripts/codex/run.sh"

RUN_LOG="$RUN_LOG_CAPTURE"
LQ="$TMPDIR/fake_lq.sh"
TEAM="KMD"
DRY_RUN=0
export LINEAR_API_KEY="test-linear-key"

repeat_char() {
  local char="$1"
  local count="$2"
  local out=""
  local i
  for ((i = 0; i < count; i += 1)); do
    out+="$char"
  done
  printf '%s' "$out"
}

OPENAI_TOKEN="sk-test$(repeat_char A 20)"
BEARER_TOKEN="$(repeat_char B 30)"
GITHUB_PAT="ghp_$(repeat_char C 36)"
GITHUB_OAUTH="gho_$(repeat_char D 36)"
LINEAR_TOKEN="lin_api_$(repeat_char E 40)"
SLACK_TOKEN="xox""b-1234567890-$(repeat_char f 26)"
AWS_TOKEN="AKIA$(repeat_char 1 16)"

INPUT_SNIPPET=$'raw '"$OPENAI_TOKEN"$' more\nBearer '"$BEARER_TOKEN"$'\nold '"$GITHUB_PAT"$'\nauto '"$GITHUB_OAUTH"$'\nlinear '"$LINEAR_TOKEN"$'\nslack '"$SLACK_TOKEN"$'\naws '"$AWS_TOKEN"$'\n``` fenced block'

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1"
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local name="$3"
  if rg -q --fixed-strings "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local name="$3"
  if rg -q --fixed-strings "$pattern" "$file"; then
    fail "$name"
  else
    pass "$name"
  fi
}

log_run 42 "quota_pattern_in_stderr" "$INPUT_SNIPPET"
create_blocked_issue "$INPUT_SNIPPET" >/dev/null

assert_contains "$RUN_LOG_CAPTURE" "***" "run log should contain redaction marker"
assert_not_contains "$RUN_LOG_CAPTURE" "$OPENAI_TOKEN" "run log should redact sk tokens"
assert_not_contains "$RUN_LOG_CAPTURE" "$GITHUB_PAT" "run log should redact GitHub tokens"
assert_not_contains "$RUN_LOG_CAPTURE" "$LINEAR_TOKEN" "run log should redact Linear tokens"
assert_contains "$ISSUE_BODY_CAPTURE" "***" "issue body should contain redaction marker"
assert_not_contains "$ISSUE_BODY_CAPTURE" "Bearer $BEARER_TOKEN" "issue body should redact bearer tokens"
assert_not_contains "$ISSUE_BODY_CAPTURE" "$SLACK_TOKEN" "issue body should redact Slack tokens"
assert_contains "$ISSUE_BODY_CAPTURE" '\`\`\` fenced block' "issue body should escape markdown fences inside snippet"

printf 'all smoke checks passed\n'
