#!/bin/bash
# host-backup-cli.sh — Non-interactive CLI backup with profile support
set -euo pipefail

HOST=""
BACKUP_USER=""
ALL=false
BACKUP_GROUPS=""
GROUPS_SET=false
HERMES_TIER="full"
HERMES_TIER_SET=false
DEST=""
DEST_SET=false
DRY_RUN=false
REDETECT=false
PROFILE=""
PROFILE_SET=false
SAVE_PROFILE=""
LIST_PROFILES=false
RESEARCH=false
DB_USER=""
DB_PASS=""
SOURCE_ARCHIVE=""
TRUSTED_SHA256=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: $0 --host HOST [options]"
  echo ""
  echo "Options:"
  echo "  --host HOST           SSH target hostname (required, except for --profile portfolio-lab)"
  echo "  --user USER           SSH user (default: agent; invalid for retrieval-only portfolio-lab)"
  echo "  --all                 Back up all groups"
  echo "  --groups 'g1,g2,...'  Specific groups: base,ssh,tailscale,caddy_domains,hermes,databases,other_services,apt,wiki"
  echo "  --profile NAME        Use a backup profile (full, quick, minimal, portfolio-lab, or custom)"
  echo "  --save-profile NAME   Save current --groups/--hermes-tier as a named profile"
  echo "  --list-profiles       List all available profiles and exit"
  echo "  --hermes-tier TIER    minimal|standard|full (default: full)"
  echo "  --dest PATH           Backup destination (default: ~/Desktop/backups/HOST/; must be absolute for portfolio-lab)"
  echo "  --dry-run             Preview only, no actual backup"
  echo "  --redetect            Re-run discovery, ignore cache"
  echo "  --research            Run post-discovery research on detected services"
  echo "  --db-user USER        Database username for pg_dump/mysqldump (default: postgres/root)"
  echo "  --db-pass PASS        Database password for mysqldump"
  echo ""
  echo "Portfolio Lab (exclusive --profile portfolio-lab; selects ONLY portfolio_lab):"
  echo "  --source-archive PATH  Explicit remote/source archive path (required; retrieval only,"
  echo "                         archive + <archive>.sha256 sidecar; no automatic cloud transfer)"
  echo "  --trusted-sha256 HEX   Independently trusted 64-character archive SHA-256 (required)"
  echo "  --dest PATH            Explicit absolute local retrieval destination (required; no default)"
  echo ""
  echo "Profiles:"
  echo "  Built-in: full (default), quick, minimal, portfolio-lab (exclusive)"
  echo "  Custom:   ~/.config/host-backup-restore/profiles.yaml"
  echo ""
  echo "Examples:"
  echo "  $0 --host sg01 --profile quick"
  echo "  $0 --host sg01 --groups 'hermes,databases' --save-profile daily"
  echo "  $0 --host sg01 --all --research"
  echo "  $0 --profile portfolio-lab --source-archive 'backup@storage.example:/mnt/encrypted-backups/portfolio-lab-YYYYMMDD.portfolio-lab-recovery.tar' \\"
  echo "     --trusted-sha256 <trusted-archive-sha256> --dest \"\$HOME/Desktop/backups/portfolio-lab/\""
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --user) BACKUP_USER="$2"; shift 2 ;;
    --all) ALL=true; shift ;;
    --groups) BACKUP_GROUPS="$2"; GROUPS_SET=true; shift 2 ;;
    --profile) PROFILE="$2"; PROFILE_SET=true; shift 2 ;;
    --save-profile) SAVE_PROFILE="$2"; shift 2 ;;
    --list-profiles) LIST_PROFILES=true; shift ;;
    --hermes-tier) HERMES_TIER="$2"; HERMES_TIER_SET=true; shift 2 ;;
    --dest) DEST="$2"; DEST_SET=true; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --redetect) REDETECT=true; shift ;;
    --research) RESEARCH=true; shift ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-pass) DB_PASS="$2"; shift 2 ;;
    --source-archive) SOURCE_ARCHIVE="$2"; shift 2 ;;
    --trusted-sha256) TRUSTED_SHA256="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# List profiles and exit
if $LIST_PROFILES; then
  source "$SCRIPT_DIR/profiles.sh"
  list_profiles
  exit 0
fi

# ── Profile/groups exclusivity (portfolio-lab) ───────────────────────────
# Never silently override a selection: --profile portfolio-lab combined with
# any --groups, or --groups portfolio_lab combined with any --profile, is
# rejected instead of one flag silently winning.
if $GROUPS_SET && $PROFILE_SET && { [ "$PROFILE" = "portfolio-lab" ] || echo "$BACKUP_GROUPS" | grep -qw portfolio_lab; }; then
  echo "Error: --profile portfolio-lab cannot be combined with --groups, and --groups portfolio_lab cannot be combined with any --profile (portfolio-lab is exclusive; it selects ONLY portfolio_lab)" >&2
  exit 1
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

# ── Portfolio-lab exclusive path ─────────────────────────────────────────
# portfolio-lab is a first-class built-in profile selecting ONLY the
# portfolio_lab group. It cannot mix with generic host/identity/Caddy/Hermes
# groups, performs no managed-host discovery, and never auto-transfers to
# cloud storage. Scope is retrieval: archive + sidecar into an explicit local
# --dest, then canonical `verify --archive` via the archive's embedded
# bootstrap. The source archive is created on the source host with the
# canonical `create` command (see SKILL.md); this path never creates it and
# makes no storage-encryption attestation.
if [ -n "$BACKUP_GROUPS" ] && echo "$BACKUP_GROUPS" | grep -qw portfolio_lab; then
  source "$SCRIPT_DIR/profiles.sh"
  if ! assert_portfolio_lab_isolated "$BACKUP_GROUPS"; then
    exit 1
  fi
  if $ALL; then
    echo "Error: portfolio-lab cannot be combined with --all (it is exclusive; selects ONLY portfolio_lab)" >&2
    exit 1
  fi
  # Fail closed on generic flags that would otherwise be silently ignored:
  # portfolio-lab backup is retrieval only — no host, no discovery, no
  # research, no database creds, no profile saving.
  if [ -n "$HOST" ] || [ -n "$BACKUP_USER" ] || $HERMES_TIER_SET || $REDETECT || $RESEARCH || [ -n "$SAVE_PROFILE" ] || [ -n "$DB_USER" ] || [ -n "$DB_PASS" ]; then
    echo "Error: --host/--user/--hermes-tier/--redetect/--research/--save-profile/--db-user/--db-pass are not valid with --profile portfolio-lab (portfolio-lab backup is retrieval only)" >&2
    exit 1
  fi
  [ -n "$SOURCE_ARCHIVE" ] || { echo "Error: --source-archive is required for portfolio-lab backup (explicit remote/source archive path)" >&2; exit 1; }
  if ! $DEST_SET; then
    echo "Error: --dest is required for portfolio-lab backup (explicit local retrieval destination; no default)" >&2
    exit 1
  fi
  [ -n "$TRUSTED_SHA256" ] || { echo "Error: --trusted-sha256 is required for portfolio-lab backup (independently trusted archive digest)" >&2; exit 1; }
  DRY_FLAG=""
  $DRY_RUN && DRY_FLAG="--dry-run"
  # shellcheck disable=SC2086
  exec bash "$SCRIPT_DIR/portfolio-lab-backup.sh" \
    --source-archive "$SOURCE_ARCHIVE" \
    --dest "$DEST" \
    --trusted-sha256 "$TRUSTED_SHA256" $DRY_FLAG
fi

# Portfolio-lab flags are only valid with the portfolio_lab group.
if [ -n "$SOURCE_ARCHIVE" ] || [ -n "$TRUSTED_SHA256" ]; then
  echo "Error: --source-archive/--trusted-sha256 are only valid with --groups portfolio_lab or --profile portfolio-lab" >&2
  exit 1
fi

if [ -z "$HOST" ]; then
  echo "Error: --host is required"
  usage
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
    match_host && /^[[:space:]]+User / { print $2; exit }
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

RAW_MANIFEST_FILE="/tmp/host-backup-${SSH_TARGET}-manifest.json"
MANIFEST_FILE="/tmp/host-backup-${HOST}-manifest.json"
python3 - "$RAW_MANIFEST_FILE" "$MANIFEST_FILE" "$HOST" "$SSH_TARGET" <<'PY'
import json
import sys

raw_path, out_path, host_label, ssh_target = sys.argv[1:]
with open(raw_path) as f:
    manifest = json.load(f)
manifest["hostname"] = host_label
if ssh_target != host_label:
    manifest["ssh_target"] = ssh_target
with open(out_path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

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
    echo "  - ssh"
    echo "  - tailscale"
    echo "  - caddy_domains"
    echo "  - hermes (tier: $HERMES_TIER)"
    echo "  - databases"
    echo "  - other_services"
    echo "  - apt"
    echo "  - wiki"
  else
    NORMALIZED=$(echo "$BACKUP_GROUPS" | tr ',' ' ')
    for g in $NORMALIZED; do
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
    SAVE_GROUPS="base ssh tailscale caddy_domains hermes databases other_services apt wiki"
  fi
  save_profile "$SAVE_PROFILE" "$SAVE_GROUPS" "$HERMES_TIER" "Custom profile saved from CLI"
  echo ""
fi

# Execute backup
export HERMES_TIER
export DB_USER
# DB_PASS is passed via environment but NOT exported to child process env
# to avoid exposure in /proc/self/environ. backup-host.sh reads it directly.
export BACKUP_DIR="$DEST"
# Pass DB_PASS securely via temp file (cleaned up on exit)
DB_PASS_FILE=""
cleanup_db_pass() {
  if [ -n "$DB_PASS_FILE" ] && [ -f "$DB_PASS_FILE" ]; then
    rm -f "$DB_PASS_FILE"
  fi
}
trap cleanup_db_pass EXIT

if [ -n "$DB_PASS" ]; then
  DB_PASS_FILE=$(mktemp)
  chmod 600 "$DB_PASS_FILE"
  echo "$DB_PASS" > "$DB_PASS_FILE"
  export DB_PASS_FILE
fi

if $ALL || [ -z "$BACKUP_GROUPS" ]; then
  bash "$SCRIPT_DIR/backup-host.sh" "$MANIFEST_FILE" all
else
  # Normalize: support both comma-separated and space-separated groups
  NORMALIZED=$(echo "$BACKUP_GROUPS" | tr ',' ' ')
  # shellcheck disable=SC2086
  bash "$SCRIPT_DIR/backup-host.sh" "$MANIFEST_FILE" $NORMALIZED
fi

echo "=== Backup complete ==="
