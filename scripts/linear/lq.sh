#!/usr/bin/env bash
# lq.sh — Linear API single entrypoint for kobaamd pipeline.
#
# All Linear I/O (subagent / slash command / pipeline / ad-hoc) goes through here.
# Self-hosted MCP equivalent: thin wrapper over Linear GraphQL with audit log,
# id caching, and --dry-run support.
#
# Env:
#   LINEAR_API_KEY  required
#   LQ_DRY_RUN=1    skip mutations, print intended payload
#
# Run `lq.sh help` for command list.

set -euo pipefail

API="https://api.linear.app/graphql"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/.logs"
WRITE_LOG="${LOG_DIR}/linear_writes.jsonl"
CACHE_FILE="${LOG_DIR}/linear_cache.json"
DRY_RUN="${LQ_DRY_RUN:-0}"

mkdir -p "$LOG_DIR"

err() { echo "lq.sh: $*" >&2; }
die() { err "$*"; exit 1; }

[[ -n "${LINEAR_API_KEY:-}" ]] || die "LINEAR_API_KEY not set. Run: source ~/.zshrc"
command -v jq   >/dev/null || die "jq required (brew install jq)"
command -v curl >/dev/null || die "curl required"

# ----- low-level GraphQL caller -----
gql() {
  local query="$1" vars="${2:-{\}}"
  local payload resp
  payload=$(jq -nc --arg q "$query" --argjson v "$vars" '{query:$q, variables:$v}')
  resp=$(curl -fsS -X POST "$API" \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$payload")
  if echo "$resp" | jq -e '.errors' >/dev/null 2>&1; then
    err "GraphQL error: $(echo "$resp" | jq -c '.errors')"
    return 1
  fi
  printf '%s' "$resp"
}

log_write() {
  local op="$1" payload="$2" resp="$3"
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --arg op "$op" \
         --argjson req "$payload" \
         --argjson resp "$resp" \
         '{ts:$ts, op:$op, req:$req, resp:$resp}' >> "$WRITE_LOG"
}

# ----- cache helpers -----
cache_get() {
  local key="$1"
  [[ -f "$CACHE_FILE" ]] || return 1
  jq -er --arg k "$key" '.[$k] // empty' "$CACHE_FILE" 2>/dev/null
}
cache_put() {
  local key="$1" val="$2"
  local tmp; tmp=$(mktemp)
  if [[ -f "$CACHE_FILE" ]]; then
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$CACHE_FILE" > "$tmp"
  else
    jq -n --arg k "$key" --arg v "$val" '{($k): $v}' > "$tmp"
  fi
  mv "$tmp" "$CACHE_FILE"
}

# ----- resolvers -----
is_uuid() { [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; }

resolve_team_id() {
  local key="$1"
  if is_uuid "$key"; then echo "$key"; return; fi
  local cached; cached=$(cache_get "team:$key" || true)
  if [[ -n "$cached" ]]; then echo "$cached"; return; fi
  local resp id
  resp=$(gql 'query($k:String!){ teams(filter:{key:{eq:$k}}){ nodes{ id } } }' \
    "$(jq -nc --arg k "$key" '{k:$k}')")
  id=$(echo "$resp" | jq -er '.data.teams.nodes[0].id') \
    || die "team '$key' not found"
  cache_put "team:$key" "$id"
  echo "$id"
}

resolve_state_id() {
  local team_key="$1" state_name="$2"
  local cache_key="state:${team_key}:${state_name}"
  local cached; cached=$(cache_get "$cache_key" || true)
  if [[ -n "$cached" ]]; then echo "$cached"; return; fi
  local team_id; team_id=$(resolve_team_id "$team_key")
  local resp id
  resp=$(gql 'query($t:String!){ team(id:$t){ states{ nodes{ id name } } } }' \
    "$(jq -nc --arg t "$team_id" '{t:$t}')")
  id=$(echo "$resp" | jq -er --arg n "$state_name" \
    '[.data.team.states.nodes[] | select(.name==$n) | .id] | .[0] // empty')
  [[ -n "$id" ]] || die "state '$state_name' not found in team '$team_key'"
  cache_put "$cache_key" "$id"
  echo "$id"
}

resolve_issue_uuid() {
  local id="$1"
  if is_uuid "$id"; then echo "$id"; return; fi
  gql 'query($id:String!){ issue(id:$id){ id } }' \
    "$(jq -nc --arg id "$id" '{id:$id}')" \
    | jq -er '.data.issue.id'
}

# ----- arg helpers -----
read_body_arg() {
  local v="$1"
  if [[ "$v" == @* ]]; then cat "${v:1}"; else printf '%s' "$v"; fi
}

# ----- read commands -----
cmd_issue_get() {
  local id="${1:?usage: issue.get <KMD-XX>}"
  gql 'query($id:String!){ issue(id:$id){ id identifier title state{name type} priority url description createdAt updatedAt labels{nodes{name}} } }' \
    "$(jq -nc --arg id "$id" '{id:$id}')" \
    | jq '.data.issue'
}

cmd_issue_list() {
  local team="" state="" limit=50
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team)  team="$2";  shift 2;;
      --state) state="$2"; shift 2;;
      --limit) limit="$2"; shift 2;;
      *) die "issue.list: unknown flag: $1";;
    esac
  done
  [[ -n "$team" ]] || die "issue.list: --team required"
  local team_id; team_id=$(resolve_team_id "$team")
  if [[ -n "$state" ]]; then
    local sid; sid=$(resolve_state_id "$team" "$state")
    gql 'query($t:ID!,$s:ID!,$n:Int!){ issues(filter:{team:{id:{eq:$t}}, state:{id:{eq:$s}}}, first:$n, orderBy:createdAt){ nodes{ identifier title state{name} priority url updatedAt } } }' \
      "$(jq -nc --arg t "$team_id" --arg s "$sid" --argjson n "$limit" '{t:$t,s:$s,n:$n}')" \
      | jq '.data.issues.nodes'
  else
    gql 'query($t:ID!,$n:Int!){ issues(filter:{team:{id:{eq:$t}}}, first:$n, orderBy:createdAt){ nodes{ identifier title state{name} priority url updatedAt } } }' \
      "$(jq -nc --arg t "$team_id" --argjson n "$limit" '{t:$t,n:$n}')" \
      | jq '.data.issues.nodes'
  fi
}

cmd_comment_list() {
  local id="${1:?usage: comment.list <KMD-XX>}"
  gql 'query($id:String!){ issue(id:$id){ comments(first:100){ nodes{ id body createdAt user{ name email } } } } }' \
    "$(jq -nc --arg id "$id" '{id:$id}')" \
    | jq '.data.issue.comments.nodes'
}

cmd_state_list() {
  local team="${1:?usage: state.list <team>}"
  local team_id; team_id=$(resolve_team_id "$team")
  gql 'query($t:String!){ team(id:$t){ states{ nodes{ id name type } } } }' \
    "$(jq -nc --arg t "$team_id" '{t:$t}')" \
    | jq '.data.team.states.nodes'
}

cmd_team_get() {
  local team="${1:?usage: team.get <team>}"
  local team_id; team_id=$(resolve_team_id "$team")
  gql 'query($t:String!){ team(id:$t){ id key name description } }' \
    "$(jq -nc --arg t "$team_id" '{t:$t}')" \
    | jq '.data.team'
}

cmd_label_list() {
  local team="${1:?usage: label.list <team>}"
  local team_id; team_id=$(resolve_team_id "$team")
  gql 'query($t:String!){ team(id:$t){ labels{ nodes{ id name color } } } }' \
    "$(jq -nc --arg t "$team_id" '{t:$t}')" \
    | jq '.data.team.labels.nodes'
}

cmd_label_create() {
  local team="" name="" color=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team)  team="$2";  shift 2;;
      --name)  name="$2";  shift 2;;
      --color) color="$2"; shift 2;;
      *) die "label.create: unknown flag: $1";;
    esac
  done
  [[ -n "$team" && -n "$name" ]] || die "label.create: --team and --name required"
  local team_id; team_id=$(resolve_team_id "$team")
  local input
  input=$(jq -nc --arg t "$team_id" --arg n "$name" '{teamId:$t, name:$n}')
  if [[ -n "$color" ]]; then
    input=$(echo "$input" | jq --arg c "$color" '. + {color:$c}')
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    jq -n --argjson i "$input" '{dryRun:true, op:"label.create", input:$i}'
    return
  fi
  local payload resp
  payload=$(jq -nc --argjson i "$input" '{input:$i}')
  resp=$(gql 'mutation($input: IssueLabelCreateInput!){ issueLabelCreate(input:$input){ success issueLabel{ id name color } } }' "$payload")
  log_write "label.create" "$payload" "$resp"
  echo "$resp" | jq '.data.issueLabelCreate.issueLabel'
}

# ----- write commands -----
cmd_issue_create() {
  local team="" state="" title="" body="" priority="" labels="" parent=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team)     team="$2"; shift 2;;
      --state)    state="$2"; shift 2;;
      --title)    title="$2"; shift 2;;
      --body)     body=$(read_body_arg "$2"); shift 2;;
      --priority) priority="$2"; shift 2;;
      --labels)   labels="$2"; shift 2;;
      --parent)   parent="$2"; shift 2;;
      *) die "issue.create: unknown flag: $1";;
    esac
  done
  [[ -n "$team" && -n "$title" ]] || die "issue.create: --team and --title required"
  local team_id; team_id=$(resolve_team_id "$team")
  local input
  input=$(jq -nc --arg t "$team_id" --arg title "$title" --arg body "$body" \
    '{teamId:$t, title:$title} + (if $body!="" then {description:$body} else {} end)')
  if [[ -n "$state" ]]; then
    local sid; sid=$(resolve_state_id "$team" "$state")
    input=$(echo "$input" | jq --arg s "$sid" '. + {stateId:$s}')
  fi
  if [[ -n "$priority" ]]; then
    input=$(echo "$input" | jq --argjson p "$priority" '. + {priority:$p}')
  fi
  if [[ -n "$labels" ]]; then
    local label_ids
    label_ids=$(echo "$labels" | jq -Rc 'split(",")')
    input=$(echo "$input" | jq --argjson l "$label_ids" '. + {labelIds:$l}')
  fi
  if [[ -n "$parent" ]]; then
    local parent_uuid; parent_uuid=$(resolve_issue_uuid "$parent")
    input=$(echo "$input" | jq --arg p "$parent_uuid" '. + {parentId:$p}')
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    jq -n --argjson i "$input" '{dryRun:true, op:"issue.create", input:$i}'
    return
  fi
  local payload resp
  payload=$(jq -nc --argjson i "$input" '{input:$i}')
  resp=$(gql 'mutation($input: IssueCreateInput!){ issueCreate(input:$input){ success issue{ id identifier title url state{name} parent{ identifier } } } }' "$payload")
  log_write "issue.create" "$payload" "$resp"
  echo "$resp" | jq '.data.issueCreate.issue'
}

# issue.relate <KMD-XX> --blocks <KMD-YY>     # XX が YY をブロック
# issue.relate <KMD-XX> --blocked-by <KMD-YY> # XX が YY にブロックされる（YY が XX をブロック）
# issue.relate <KMD-XX> --related <KMD-YY>    # 関連
cmd_issue_relate() {
  local id="${1:?usage: issue.relate <KMD-XX> --blocks|--blocked-by|--related <KMD-YY>}"; shift
  local flag="${1:?missing relation flag}"; shift
  local target="${1:?missing target ID}"; shift

  local issue_uuid target_uuid type rel_issue rel_related
  issue_uuid=$(resolve_issue_uuid "$id")
  target_uuid=$(resolve_issue_uuid "$target")

  case "$flag" in
    --blocks)
      type="blocks"; rel_issue="$issue_uuid"; rel_related="$target_uuid";;
    --blocked-by)
      type="blocks"; rel_issue="$target_uuid"; rel_related="$issue_uuid";;
    --related)
      type="related"; rel_issue="$issue_uuid"; rel_related="$target_uuid";;
    *) die "issue.relate: unknown flag: $flag";;
  esac

  local input
  input=$(jq -nc --arg i "$rel_issue" --arg r "$rel_related" --arg t "$type" \
    '{issueId:$i, relatedIssueId:$r, type:$t}')
  if [[ "$DRY_RUN" == "1" ]]; then
    jq -n --arg id "$id" --arg target "$target" --arg flag "$flag" --argjson i "$input" \
      '{dryRun:true, op:"issue.relate", from:$id, flag:$flag, to:$target, input:$i}'
    return
  fi
  local payload resp
  payload=$(jq -nc --argjson i "$input" '{input:$i}')
  resp=$(gql 'mutation($input: IssueRelationCreateInput!){ issueRelationCreate(input:$input){ success issueRelation{ id type issue{ identifier } relatedIssue{ identifier } } } }' "$payload")
  log_write "issue.relate" "$payload" "$resp"
  echo "$resp" | jq '.data.issueRelationCreate.issueRelation'
}

cmd_issue_update() {
  local id="${1:?usage: issue.update <KMD-XX> [flags]}"; shift
  local input='{}'
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)    input=$(echo "$input" | jq --arg v "$2" '. + {title:$v}'); shift 2;;
      --body)
        local b; b=$(read_body_arg "$2")
        input=$(echo "$input" | jq --arg v "$b" '. + {description:$v}'); shift 2;;
      --priority) input=$(echo "$input" | jq --argjson v "$2" '. + {priority:$v}'); shift 2;;
      --state)
        local team="${id%%-*}" sid
        sid=$(resolve_state_id "$team" "$2")
        input=$(echo "$input" | jq --arg v "$sid" '. + {stateId:$v}'); shift 2;;
      --labels)
        local ids; ids=$(echo "$2" | jq -Rc 'split(",")')
        input=$(echo "$input" | jq --argjson v "$ids" '. + {labelIds:$v}'); shift 2;;
      *) die "issue.update: unknown flag: $1";;
    esac
  done
  if [[ "$DRY_RUN" == "1" ]]; then
    jq -n --arg id "$id" --argjson i "$input" '{dryRun:true, op:"issue.update", id:$id, input:$i}'
    return
  fi
  local payload resp
  payload=$(jq -nc --arg id "$id" --argjson i "$input" '{id:$id, input:$i}')
  resp=$(gql 'mutation($id:String!,$input:IssueUpdateInput!){ issueUpdate(id:$id, input:$input){ success issue{ identifier title state{name} priority } } }' "$payload")
  log_write "issue.update" "$payload" "$resp"
  echo "$resp" | jq '.data.issueUpdate.issue'
}

cmd_issue_transition() {
  local id="${1:?usage: issue.transition <KMD-XX> <state-name>}"
  local state="${2:?usage: issue.transition <KMD-XX> <state-name>}"
  local team="${id%%-*}"
  local sid; sid=$(resolve_state_id "$team" "$state")
  if [[ "$DRY_RUN" == "1" ]]; then
    jq -n --arg id "$id" --arg s "$sid" --arg sn "$state" '{dryRun:true, op:"issue.transition", id:$id, toState:$sn, stateId:$s}'
    return
  fi
  local payload resp
  payload=$(jq -nc --arg id "$id" --arg s "$sid" '{id:$id, input:{stateId:$s}}')
  resp=$(gql 'mutation($id:String!,$input:IssueUpdateInput!){ issueUpdate(id:$id, input:$input){ success issue{ identifier state{name} } } }' "$payload")
  log_write "issue.transition" "$payload" "$resp"
  echo "$resp" | jq '.data.issueUpdate.issue'
}

cmd_issue_archive() {
  local id="${1:?usage: issue.archive <KMD-XX>}"
  if [[ "$DRY_RUN" == "1" ]]; then
    jq -n --arg id "$id" '{dryRun:true, op:"issue.archive", id:$id}'
    return
  fi
  local payload resp
  payload=$(jq -nc --arg id "$id" '{id:$id}')
  resp=$(gql 'mutation($id:String!){ issueArchive(id:$id){ success } }' "$payload")
  log_write "issue.archive" "$payload" "$resp"
  echo "$resp" | jq '.data.issueArchive'
}

cmd_comment_add() {
  local id="${1:?usage: comment.add <KMD-XX> @file|str}"
  local body; body=$(read_body_arg "${2:?usage: comment.add <KMD-XX> @file|str}")
  local issue_uuid; issue_uuid=$(resolve_issue_uuid "$id")
  if [[ "$DRY_RUN" == "1" ]]; then
    jq -n --arg id "$id" --arg uuid "$issue_uuid" --arg b "$body" \
      '{dryRun:true, op:"comment.add", id:$id, issueUuid:$uuid, body:$b}'
    return
  fi
  local payload resp
  payload=$(jq -nc --arg uuid "$issue_uuid" --arg b "$body" '{input:{issueId:$uuid, body:$b}}')
  resp=$(gql 'mutation($input:CommentCreateInput!){ commentCreate(input:$input){ success comment{ id body url } } }' "$payload")
  log_write "comment.add" "$payload" "$resp"
  echo "$resp" | jq '.data.commentCreate.comment'
}

# ----- meta -----
cmd_cache_clear() {
  rm -f "$CACHE_FILE"
  echo '{"cleared":true}'
}

usage() {
  cat <<'EOF'
lq.sh — Linear API single entrypoint

READ:
  issue.get      <KMD-XX>
  issue.list     --team <key> [--state <name>] [--limit N]
  comment.list   <KMD-XX>
  state.list     <team>
  team.get       <team>
  label.list     <team>

WRITE (logged to .logs/linear_writes.jsonl):
  issue.create   --team <key> --title <t> [--state <name>] [--body @file|str]
                 [--priority 0..4] [--labels id1,id2] [--parent <KMD-XX>]
  issue.update   <KMD-XX> [--title <t>] [--body @file|str] [--priority N]
                 [--state <name>] [--labels id1,id2]
  issue.transition <KMD-XX> <state-name>
  issue.archive  <KMD-XX>
  issue.relate   <KMD-XX> --blocks|--blocked-by|--related <KMD-YY>
  label.create   --team <key> --name <name> [--color "#RRGGBB"]
  comment.add    <KMD-XX> @file|literal-text

META:
  cache.clear    invalidate id cache
  help

ENV:
  LINEAR_API_KEY (required)
  LQ_DRY_RUN=1   print intended mutation, no API call

Notes:
  - <team> can be team key (e.g., KMD) or UUID
  - <state-name> is the state's display name (e.g., "draft", "Todo", "In Progress")
  - --body / comment body: prefix with @ to read from a file (e.g., @/tmp/body.md)
  - all mutations append a JSONL record to .logs/linear_writes.jsonl for audit
EOF
}

# ----- dispatch -----
case "${1:-help}" in
  issue.get)        shift; cmd_issue_get "$@";;
  issue.list)       shift; cmd_issue_list "$@";;
  issue.create)     shift; cmd_issue_create "$@";;
  issue.update)     shift; cmd_issue_update "$@";;
  issue.transition) shift; cmd_issue_transition "$@";;
  issue.archive)    shift; cmd_issue_archive "$@";;
  issue.relate)     shift; cmd_issue_relate "$@";;
  comment.list)     shift; cmd_comment_list "$@";;
  comment.add)      shift; cmd_comment_add "$@";;
  state.list)       shift; cmd_state_list "$@";;
  team.get)         shift; cmd_team_get "$@";;
  label.list)       shift; cmd_label_list "$@";;
  label.create)     shift; cmd_label_create "$@";;
  cache.clear)      shift; cmd_cache_clear "$@";;
  help|--help|-h)   usage;;
  *) err "unknown command: $1"; usage; exit 1;;
esac
