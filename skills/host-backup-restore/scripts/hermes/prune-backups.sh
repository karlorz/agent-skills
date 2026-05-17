#!/bin/bash
# ============================================================================
# prune-backups.sh — Retention/pruning for local Hermes backup archives
# ============================================================================
# Keeps N most recent backup sets per host directory under DEST_ROOT.
# A "backup set" = all files sharing a timestamp prefix (e.g.,
# hermes-20260517-*.zip, hermes-profiles-20260517-*.tar.gz).
#
# Usage:
#   bash prune-backups.sh <dest-root> [--retain <N>] [--dry-run]
#
# Examples:
#   bash prune-backups.sh ~/Desktop/backups --retain 7
#   bash prune-backups.sh ~/Desktop/backups --retain 14 --dry-run
# ============================================================================

set -euo pipefail

# Allow empty globs so ls *.zip doesn't fail when no backups exist
shopt -s nullglob

DEST_ROOT="${1:-}"
RETAIN=7
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --retain) RETAIN="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: prune-backups.sh <dest-root> [--retain <N>] [--dry-run]"
      exit 0 ;;
    *)
      # first non-flag arg is dest-root
      [ -z "$DEST_ROOT" ] && DEST_ROOT="$1" && shift || { echo "ERROR: Unknown: $1" >&2; exit 1; } ;;
  esac
done

[ -z "$DEST_ROOT" ] && { echo "ERROR: <dest-root> is required" >&2; exit 1; }
[ ! -d "$DEST_ROOT" ] && { echo "ERROR: Directory not found: $DEST_ROOT" >&2; exit 1; }

TOTAL_REMOVED=0
TOTAL_SAVED=0

for HOST_DIR in "$DEST_ROOT"/*/; do
  [ -d "$HOST_DIR" ] || continue
  HOST=$(basename "$HOST_DIR")

  # Collect unique backup timestamp prefixes (YYYYMMDD-HHMMSS) from zip/tgz files
  # Sort descending so newest are kept
  TIMESTAMPS=$(ls -1 "$HOST_DIR"/*.zip "$HOST_DIR"/*.tar.gz 2>/dev/null \
    | sed -n 's/.*hermes[-a-z]*-\([0-9]\{8\}-[0-9]\{6\}\)\(\..*\)/\1/p' \
    | sort -r -u)

  TIMESTAMP_COUNT=$(echo "$TIMESTAMPS" | grep -c . 2>/dev/null || echo 0)

  if [ "$TIMESTAMP_COUNT" -le "$RETAIN" ]; then
    echo "  $HOST: $TIMESTAMP_COUNT sets (<= $RETAIN, nothing to prune)"
    TOTAL_SAVED=$((TOTAL_SAVED + TIMESTAMP_COUNT))
    continue
  fi

  # Keep first RETAIN (newest), remove the rest
  TO_KEEP=$(echo "$TIMESTAMPS" | head -n "$RETAIN")
  TO_REMOVE=$(echo "$TIMESTAMPS" | tail -n +$((RETAIN + 1)))

  REMOVED_COUNT=0
  TS_LIST=""

  while IFS= read -r ts; do
    [ -z "$ts" ] && continue
    for f in "$HOST_DIR"/*"$ts"*; do
      if $DRY_RUN; then
        echo "  [DRY-RUN] Would delete: $(basename "$f")"
      else
        rm -f "$f"
        echo "  Deleted: $(basename "$f")"
      fi
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    done
    TS_LIST="$TS_LIST $ts"
  done <<< "$TO_REMOVE"

  TOTAL_REMOVED=$((TOTAL_REMOVED + REMOVED_COUNT))
  TOTAL_SAVED=$((TOTAL_SAVED + RETAIN))

  if $DRY_RUN; then
    echo "  $HOST: would prune $REMOVED_COUNT files, keep $RETAIN sets"
  else
    echo "  $HOST: pruned $REMOVED_COUNT files, kept $RETAIN sets"
  fi
done

echo ""
echo "=== Prune Summary ==="
echo "  Retained: $TOTAL_SAVED sets"
echo "  Removed:  $TOTAL_REMOVED files"
