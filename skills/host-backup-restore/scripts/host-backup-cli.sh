#!/bin/bash
# host-backup-cli.sh — Non-interactive CLI backup with profile support
set -euo pipefail

HOST=""
BACKUP_USER=""
ALL=false
BACKUP_GROUPS=""
HERMES_TIER="full"
DEST=""
DRY_RUN=false
REDETECT=false
PROFILE=""
SAVE_PROFILE=""
LIST_PROFILES=false
RESEARCH=false

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: $0 --host HOST [options]"
  echo ""
  echo "Options:"
  echo "  --host HOST           SSH target hostname (required)"
  echo "  --user USER           SSH user (default: root; or use host-agent SSH alias for non-root)"
  echo "  --all                 Back up all groups"
  echo "  --groups 'g1,g2,...'  Specific groups: base,caddy_domains,hermes,databases,other_services,apt"
  echo "  --profile NAME        Use a backup profile (full, quick, minimal, or custom)"
  echo "  --save-profile NAME   Save current --groups/--hermes-tier as a named profile"
  echo "  --list-profiles       List all available profiles and exit"
  echo "  --hermes-tier TIER    minimal|standard|full (default: full)"
  echo "  --dest PATH           Backup destination (default: ~/Desktop/backups/HOST/)"
  echo "  --dry-run             Preview only, no actual backup"
  echo "  --redetect            Re-run discovery, ignore cache"
  echo "  --research            Run post-discovery research on detected services"
  echo ""
  echo "Profiles:"
  echo "  Built-in: full (default), quick, minimal"
  echo "  Custom:   ~/.config/host-backup-restore/profiles.yaml"
  echo ""
  echo "Examples:"
  echo "  $0 --host sg01 --profile quick"
  echo "  $0 --host sg01 --groups 'hermes,databases' --save-profile daily"
  echo "  $0 --host sg01 --all --research"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --user) BACKUP_USER="$2"; shift 2 ;;
    --all) ALL=true; shift ;;
    --groups) BACKUP_GROUPS="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --save-profile) SAVE_PROFILE="$2"; shift 2 ;;
    --list-profiles) LIST_PROFILES=true; shift ;;
    --hermes-tier) HERMES_TIER="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --redetect) REDETECT=true; shift ;;
    --research) RESEARCH=true; shift ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# List profiles and exit
if $LIST_PROFILES; then
  source "$SCRIPT_DIR/profiles.sh"
  list_profiles
  exit 0
fi

if [ -z "$HOST" ]; then
  echo "Error: --host is required"
  usage
fi

# Resolve profile if specified
if [ -n "$PROFILE" ]; then
  source "$SCRIPT_DIR/profiles.sh"
  if resolve_profile "$PROFILE"; then
    BACKUP_GROUPS="$PROFILE_GROUPS"
    HERMES_TIER="$PROFILE_HERMES_TIER"
    echo "Using profile: $PROFILE"
    echo "  Groups: $BACKUP_GROUPS"
    echo "  Hermes tier: $HERMES_TIER"
    [ -n "$PROFILE_DESCRIPTION" ] && echo "  Description: $PROFILE_DESCRIPTION"
    echo ""
  else
    exit 1
  fi
fi

# Compose SSH target — resolve user from ~/.ssh/config if available
# Priority: --user flag > SSH config User directive > agent@ default
if [ -n "$BACKUP_USER" ]; then
  SSH_TARGET="${BACKUP_USER}@${HOST}"
elif [[ "$HOST" == *@* ]]; then
  # Already user@host format — use as-is
  SSH_TARGET="$HOST"
elif [[ "$HOST" == *-agent ]]; then
  # SSH config alias (e.g., sg01-agent with User agent in ~/.ssh/config) — use as-is
  SSH_TARGET="$HOST"
else
  # Check ~/.ssh/config for User directive matching this host
  ssh_config_user=$(awk -v host="$HOST" '
    /^Host / { match_host=0; for(i=2;i<=NF;i++) if($i==host) match_host=1 }
    match_host && /^  User / { print $2; found=1; exit }
  ' ~/.ssh/config 2>/dev/null)
  if [ -n "$ssh_config_user" ]; then
    SSH_TARGET="${ssh_config_user}@${HOST}"
    echo "Using SSH config user: ${ssh_config_user}@${HOST}"
  else
    # Default: use non-root agent user
    SSH_TARGET="agent@${HOST}"
  fi
fi
export SSH_TARGET

DEST="${DEST:-$HOME/Desktop/backups/$HOST}"

echo "=== Host Backup CLI ==="
echo "Host:     $HOST"
[ -n "$BACKUP_USER" ] && echo "User:     $BACKUP_USER"
echo "Dest:     $DEST"
echo "Dry run:  $DRY_RUN"
[ -n "$BACKUP_GROUPS" ] && echo "Groups:   $BACKUP_GROUPS"
echo "Hermes:   $HERMES_TIER"
echo ""

# Run discovery (pass SSH_TARGET as host for user@host support)
REDETECT_FLAG=""
$REDETECT && REDETECT_FLAG="--redetect"
MANIFEST=$(bash "$SCRIPT_DIR/discover.sh" "$SSH_TARGET" $REDETECT_FLAG)
echo "$MANIFEST" | python3 -m json.tool 2>/dev/null || echo "$MANIFEST"

MANIFEST_FILE="/tmp/host-backup-${HOST}-manifest.json"

# Post-discovery research
if $RESEARCH; then
  echo ""
  echo "=== Running post-discovery research ==="
  bash "$SCRIPT_DIR/research-host.sh" "$MANIFEST_FILE" --output "/tmp/host-backup-${HOST}-research" || true
  echo ""
fi

if $DRY_RUN; then
  echo ""
  echo "=== DRY RUN ==="
  echo "Would back up:"
  if $ALL || [ -z "$BACKUP_GROUPS" ]; then
    echo "  - base"
    echo "  - caddy_domains"
    echo "  - hermes (tier: $HERMES_TIER)"
    echo "  - databases"
    echo "  - other_services"
    echo "  - apt"
  else
    IFS=',' read -ra GROUP_ARRAY <<< "$BACKUP_GROUPS"
    for g in "${GROUP_ARRAY[@]}"; do
      echo "  - $g"
    done
  fi
  echo "Destination: $DEST"
  echo "=== Dry run complete (no files written) ==="
  exit 0
fi

# Save profile if requested
if [ -n "$SAVE_PROFILE" ]; then
  source "$SCRIPT_DIR/profiles.sh"
  SAVE_GROUPS="$BACKUP_GROUPS"
  if $ALL || [ -z "$BACKUP_GROUPS" ]; then
    SAVE_GROUPS="base caddy_domains hermes databases other_services apt"
  fi
  save_profile "$SAVE_PROFILE" "$SAVE_GROUPS" "$HERMES_TIER" "Custom profile saved from CLI"
  echo ""
fi

# Execute backup
export HERMES_TIER
export BACKUP_DIR="$DEST"

if $ALL || [ -z "$BACKUP_GROUPS" ]; then
  bash "$SCRIPT_DIR/backup-host.sh" "$MANIFEST_FILE" all
else
  # Normalize: support both comma-separated and space-separated groups
  NORMALIZED=$(echo "$BACKUP_GROUPS" | tr ',' ' ')
  # shellcheck disable=SC2086
  bash "$SCRIPT_DIR/backup-host.sh" "$MANIFEST_FILE" $NORMALIZED
fi

echo "=== Backup complete ==="
