#!/bin/bash
# ============================================================================
# host-restore-cli.sh — Non-interactive CLI wrapper for remote Hermes restore
# ============================================================================
# Usage:
#   bash host-restore-cli.sh --archive ~/Desktop/backups/sg01/hermes-20260516-full.zip --target sg01
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE=""
TARGET=""
NON_ROOT_USER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) ARCHIVE="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --non-root-user) NON_ROOT_USER="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: host-restore-cli.sh --archive <path> --target <host> [--non-root-user <user>]" >&2
      exit 0 ;;
    *) echo "ERROR: Unknown option $1" >&2; exit 1 ;;
  esac
done

[ -z "$ARCHIVE" ] && { echo "ERROR: --archive is required" >&2; exit 1; }
[ -z "$TARGET" ] && { echo "ERROR: --target is required" >&2; exit 1; }

CMD_ARGS="--target $TARGET"
[ -n "$NON_ROOT_USER" ] && CMD_ARGS="$CMD_ARGS --non-root-user $NON_ROOT_USER"

exec bash "$SCRIPT_DIR/remote-restore.sh" "$ARCHIVE" $CMD_ARGS