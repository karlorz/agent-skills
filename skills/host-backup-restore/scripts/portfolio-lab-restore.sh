#!/bin/bash
# portfolio-lab-restore.sh — Portfolio Lab bundle restore (portfolio_lab group)
#
# Transfers one explicit plaintext recovery archive and its sidecar, compares
# its bytes against an independently trusted SHA-256, validates only the
# embedded bootstrap with a stdlib tarfile gate, then uses that bootstrap to
# run canonical verify before canonical restore. It never full-extracts and
# never auto-activates production; staging is retained after success so the
# printed attended activation command remains usable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE=""
TARGET=""
TARGET_MODE=""
APP_DIR=""
WEB_ROOT=""
TASKER_SERVICE=""
TRUSTED_SHA256=""
ALLOW_PRODUCTION_PATHS=false
START_DEV_API=false
DRY_RUN=false
SSH_OPTS=(-o ConnectTimeout=10 -o BatchMode=yes)
REMOTE_DIR=""
SUCCESS=false

usage() {
  cat <<'EOF'
Usage: portfolio-lab-restore.sh [options]

Restore a Portfolio Lab recovery archive from trusted storage using its embedded
canonical recovery CLI. The wrapper transfers the plaintext
.portfolio-lab-recovery.tar plus its .sha256 sidecar, safely extracts only the
bootstrap, runs `verify --archive`, then runs canonical `restore`. Production
activation is printed only.

Options:
  --archive PATH             Local plaintext .portfolio-lab-recovery.tar (required)
  --target HOST              Safe SSH alias or user@host (required)
  --target-mode dev|prod     Explicit target mode (required)
  --app-dir PATH             Absolute application directory on target (required)
  --web-root PATH            Absolute web root on target (required)
  --trusted-sha256 HEX       Independently trusted 64-character archive SHA-256 (required)
  --tasker-service NAME      Optional safe systemd unit name
  --allow-production-paths   Canonical prod restore flag
  --start-dev-api            Canonical dev restore flag
  --dry-run                  Print actions without ssh/rsync side effects
  -h, --help                 Show this help
EOF
}

die() {
  echo "Error: $1" >&2
  exit 1
}

safe_path() {
  local label="$1" value="$2"
  [[ "$value" == /* ]] || die "unsafe $label: must be an absolute path"
  [[ "$value" =~ ^/[A-Za-z0-9._/@+=:%,-]+$ ]] || die "unsafe $label"
}

safe_target() {
  [[ "$TARGET" =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || die "unsafe target"
  [[ "$TARGET" != -* ]] || die "unsafe target"
}

safe_service() {
  [ -z "$TASKER_SERVICE" ] || [[ "$TASKER_SERVICE" =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || die "unsafe --tasker-service"
}

remote_quote() {
  local value="$1"
  value=${value//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

remote_run() {
  local command="$1"
  ssh "${SSH_OPTS[@]}" -- "$TARGET" "$command"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --archive) ARCHIVE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --target-mode) TARGET_MODE="${2:-}"; shift 2 ;;
    --app-dir) APP_DIR="${2:-}"; shift 2 ;;
    --web-root) WEB_ROOT="${2:-}"; shift 2 ;;
    --trusted-sha256) TRUSTED_SHA256="${2:-}"; shift 2 ;;
    --tasker-service) TASKER_SERVICE="${2:-}"; shift 2 ;;
    --allow-production-paths) ALLOW_PRODUCTION_PATHS=true; shift ;;
    --start-dev-api) START_DEV_API=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -n "$ARCHIVE" ] || die "--archive is required"
[ -f "$ARCHIVE" ] || die "Archive not found: $ARCHIVE"
[ -n "$TARGET" ] || die "--target is required"
[ -n "$APP_DIR" ] || die "--app-dir is required"
[ -n "$WEB_ROOT" ] || die "--web-root is required"
[[ "$TRUSTED_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "--trusted-sha256 must be 64 lowercase hex from an independently trusted source"
case "$TARGET_MODE" in dev|prod) ;; *) die "--target-mode must be dev or prod" ;; esac
command -v rsync >/dev/null 2>&1 || die "rsync is required"

ARCHIVE_NAME=$(basename "$ARCHIVE")
case "$ARCHIVE_NAME" in
  *.portfolio-lab-recovery.tar) ;;
  *) die "unsafe archive filename: require a canonical portfolio-lab recovery .tar" ;;
esac
SIDECAR="$ARCHIVE.sha256"
[ -f "$SIDECAR" ] || die "checksum sidecar not found: $SIDECAR"
safe_target
safe_path "--app-dir" "$APP_DIR"
safe_path "--web-root" "$WEB_ROOT"
safe_service

# Each restore receives a new owner-only staging directory. Its path is
# retained after success so the operator can run the printed activation command.
if $DRY_RUN; then
  cat <<EOF
=== DRY RUN ===
Would create a private remote staging directory on $TARGET.
Would transfer $ARCHIVE_NAME and its sidecar into that directory.
Would compare the archive bytes to the independently trusted SHA-256.
Would validate archive members and extract only the bootstrap.
Would run canonical verify before canonical restore ($TARGET_MODE).
No ssh, rsync, or remote cleanup is performed.
EOF
  exit 0
fi

REMOTE_DIR=$(remote_run 'umask 077; mktemp -d /tmp/portfolio-lab-restore.XXXXXX') || die "cannot prepare target staging"
case "$REMOTE_DIR" in
  /tmp/portfolio-lab-restore.[A-Za-z0-9][A-Za-z0-9]*) ;;
  *) die "target returned an unsafe staging directory" ;;
esac
remote_run "chmod 700 $(remote_quote "$REMOTE_DIR")" || die "cannot secure target staging"

cleanup_remote() {
  if ! $SUCCESS && [ -n "$REMOTE_DIR" ]; then
    remote_run "rm -rf $(remote_quote "$REMOTE_DIR")" >/dev/null 2>&1 || true
  fi
}
trap cleanup_remote EXIT

rsync -avP --partial-dir=.rsync-partial --timeout=300 -e "ssh ${SSH_OPTS[*]}" \
  "$ARCHIVE" "$SIDECAR" "${TARGET}:${REMOTE_DIR}/" || die "transfer to target failed"

expected=$(awk 'NF == 2 {print $1; exit}' "$SIDECAR" 2>/dev/null || true)
remote_hash=$(remote_run "cd $(remote_quote "$REMOTE_DIR") && (sha256sum $(remote_quote "$ARCHIVE_NAME") 2>/dev/null || shasum -a 256 $(remote_quote "$ARCHIVE_NAME")) | awk '{print \$1}'" 2>/dev/null || true)
if [ -z "$expected" ] || [ "$expected" != "$remote_hash" ]; then
  die "checksum mismatch on target"
fi
if [ "$TRUSTED_SHA256" != "$remote_hash" ]; then
  die "trusted archive digest mismatch on target"
fi

echo "Checksum and trusted digest verified on target: $remote_hash"

if ! remote_run "python3 - $(remote_quote "$REMOTE_DIR/$ARCHIVE_NAME") $(remote_quote "$REMOTE_DIR/tools")" < "$SCRIPT_DIR/portfolio_lab_archive.py"; then
  die "safe archive validation failed for $ARCHIVE_NAME"
fi

if ! remote_run "cd $(remote_quote "$REMOTE_DIR/tools") && python3 portfolio_lab_recovery.py verify --archive $(remote_quote "$REMOTE_DIR/$ARCHIVE_NAME")"; then
  die "canonical verify failed on target; restore aborted"
fi

restore_cmd="cd $(remote_quote "$REMOTE_DIR/tools") && python3 portfolio_lab_recovery.py restore --archive $(remote_quote "$REMOTE_DIR/$ARCHIVE_NAME") --app-dir $(remote_quote "$APP_DIR") --web-root $(remote_quote "$WEB_ROOT") --target-mode $(remote_quote "$TARGET_MODE")"
$ALLOW_PRODUCTION_PATHS && restore_cmd+=" --allow-production-paths"
$START_DEV_API && restore_cmd+=" --start-dev-api"
[ -z "$TASKER_SERVICE" ] || restore_cmd+=" --tasker-service $(remote_quote "$TASKER_SERVICE")"
remote_run "$restore_cmd" || die "canonical restore failed on target"

SUCCESS=true
echo "=== Portfolio Lab restore complete (target-mode: $TARGET_MODE) ==="
echo "Staging retained for attended activation: $REMOTE_DIR"
if [ -n "$TASKER_SERVICE" ]; then
  activation_service="$TASKER_SERVICE"
else
  activation_service="<tasker-service>"
fi
echo "Manual production activation only (never run by this wrapper):"
echo "  cd $(remote_quote "$REMOTE_DIR/tools") && python3 portfolio_lab_recovery.py activate-prod --app-dir $(remote_quote "$APP_DIR") --web-root $(remote_quote "$WEB_ROOT") --tasker-service $(remote_quote "$activation_service") --confirm-authoritative-activation --former-authority-confirmed-stopped <LABEL>"
echo "After the attended operation, clean up: ssh ${TARGET} $(remote_quote "rm -rf $REMOTE_DIR")"
