#!/bin/bash
# ============================================================================
# host-backup-cli.sh — Non-interactive CLI wrapper for remote Hermes backup
# ============================================================================
# Usage:
#   bash host-backup-cli.sh --host sg01 --mode full
#   bash host-backup-cli.sh --host sg01 --mode quick --include-profiles --include-systemd
#   bash host-backup-cli.sh --host sg02-agent --mode full --retain 7 --upload idrive:hermes-backups/sg02/
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST=""
MODE="full"
declare -a EXTRA_ARGS=()
DEST="$HOME/Desktop/backups"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --include-profiles) EXTRA_ARGS+=(--include-profiles); shift ;;
    --include-systemd) EXTRA_ARGS+=(--include-systemd); shift ;;
    --include-rclone-config) EXTRA_ARGS+=(--include-rclone-config); shift ;;
    --dest) DEST="$2"; shift 2 ;;
    --retain) EXTRA_ARGS+=(--retain "$2"); shift 2 ;;
    --upload) EXTRA_ARGS+=(--upload "$2"); shift 2 ;;
    --help|-h)
      echo "Usage: host-backup-cli.sh --host <host> [--mode quick|full] [--include-profiles] [--include-systemd] [--include-rclone-config] [--dest <path>] [--retain <N>] [--upload <remote>:<path>]"
      exit 0 ;;
    *) echo "ERROR: Unknown option $1" >&2; exit 1 ;;
  esac
done

[ -z "$HOST" ] && { echo "ERROR: --host is required" >&2; exit 1; }

exec bash "$SCRIPT_DIR/remote-backup.sh" "$HOST" \
  --mode "$MODE" "${EXTRA_ARGS[@]}" \
  --dest "$DEST"