#!/usr/bin/env bash
# Configure development-only Keychain partition lists for kobaamd API keys.
#
# This intentionally does not run from post-build.sh. Updating Keychain ACLs is
# a local developer setup action and may require an interactive macOS password
# prompt from the `security` command.

set -euo pipefail

SERVICE="${KOBAAMD_KEYCHAIN_SERVICE:-com.kobaamd.apikeys}"
KEYCHAIN="${KOBAAMD_KEYCHAIN:-}"
PARTITION_LIST="${KOBAAMD_KEYCHAIN_PARTITIONS:-apple-tool:,apple:}"
APPLY=0
ALLOW_UNSIGNED=0
ACCOUNTS=()
DEFAULT_ACCOUNTS=(openai anthropic confluenceURL confluenceEmail confluenceToken)

usage() {
  cat <<'EOF'
Usage: scripts/keychain/configure-dev-acl.sh [options]

Sets the partition list for existing kobaamd generic-password Keychain items.
The default mode is dry-run. Pass --apply to perform changes.

Options:
  --apply                         Mutate matching Keychain items.
  --dry-run                       Print intended changes only (default).
  --allow-unsigned-dev-app        Add unsigned: for ad-hoc development builds.
  --service <name>                Keychain service name (default: com.kobaamd.apikeys).
  --account <name>                Account to update. Repeatable.
  --accounts <a,b,c>              Comma-separated accounts to update.
  --keychain <path-or-name>       Keychain path/name (default: user default keychain).
  --partition-list <list>         Override partition list.
  -h, --help                      Show this help.

Examples:
  scripts/keychain/configure-dev-acl.sh
  scripts/keychain/configure-dev-acl.sh --allow-unsigned-dev-app --apply
  scripts/keychain/configure-dev-acl.sh --account openai --allow-unsigned-dev-app --apply

Notes:
  - The script never reads, accepts, or prints API keys.
  - `security` may ask for the login keychain password when --apply is used.
  - Use --allow-unsigned-dev-app only for a local development keychain.
EOF
}

die() {
  echo "configure-dev-acl: $*" >&2
  exit 1
}

append_partition() {
  local token="$1"
  case ",$PARTITION_LIST," in
    *",$token,"*) ;;
    *) PARTITION_LIST="${PARTITION_LIST},${token}" ;;
  esac
}

split_accounts() {
  local csv="$1"
  local item
  IFS=',' read -r -a _split_accounts <<< "$csv"
  for item in "${_split_accounts[@]}"; do
    [[ -n "$item" ]] && ACCOUNTS+=("$item")
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --dry-run)
      APPLY=0
      shift
      ;;
    --allow-unsigned-dev-app)
      ALLOW_UNSIGNED=1
      shift
      ;;
    --service)
      SERVICE="${2:?--service requires a value}"
      shift 2
      ;;
    --account)
      ACCOUNTS+=("${2:?--account requires a value}")
      shift 2
      ;;
    --accounts)
      split_accounts "${2:?--accounts requires a value}"
      shift 2
      ;;
    --keychain)
      KEYCHAIN="${2:?--keychain requires a value}"
      shift 2
      ;;
    --partition-list)
      PARTITION_LIST="${2:?--partition-list requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

command -v security >/dev/null || die "macOS security command is required"

if [[ "$ALLOW_UNSIGNED" == "1" ]]; then
  append_partition "unsigned:"
fi

if [[ ${#ACCOUNTS[@]} -eq 0 ]]; then
  ACCOUNTS=("${DEFAULT_ACCOUNTS[@]}")
fi

[[ -n "$SERVICE" ]] || die "service must not be empty"
[[ -n "$PARTITION_LIST" ]] || die "partition list must not be empty"
[[ "$SERVICE" != *$'\n'* ]] || die "service must be a single line"
[[ "$PARTITION_LIST" =~ ^[A-Za-z0-9_:+.,-]+$ ]] || die "partition list contains unsupported characters"

if [[ -z "$KEYCHAIN" ]]; then
  KEYCHAIN="$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
fi
[[ -n "$KEYCHAIN" ]] || die "could not resolve default keychain"
[[ "$KEYCHAIN" != *$'\n'* ]] || die "keychain must be a single line"

echo "[keychain-acl] service: $SERVICE"
echo "[keychain-acl] keychain: $KEYCHAIN"
echo "[keychain-acl] partition-list: $PARTITION_LIST"
if [[ "$APPLY" == "1" ]]; then
  echo "[keychain-acl] mode: apply"
else
  echo "[keychain-acl] mode: dry-run (pass --apply to modify matching items)"
fi

updated=0
skipped=0

for account in "${ACCOUNTS[@]}"; do
  [[ -n "$account" ]] || die "account must not be empty"
  [[ "$account" != *$'\n'* ]] || die "account must be a single line"

  if ! security find-generic-password -s "$SERVICE" -a "$account" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "[keychain-acl] skip missing item: account=$account"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$APPLY" == "1" ]]; then
    security set-generic-password-partition-list \
      -s "$SERVICE" \
      -a "$account" \
      -S "$PARTITION_LIST" \
      "$KEYCHAIN" >/dev/null
    echo "[keychain-acl] updated: account=$account"
  else
    echo "[keychain-acl] would update: account=$account"
  fi
  updated=$((updated + 1))
done

echo "[keychain-acl] done: matched=$updated skipped=$skipped"
