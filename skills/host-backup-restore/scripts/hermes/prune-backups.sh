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

# Allow empty globs so pattern loops don't fail when no backups exist
shopt -s nullglob

DEST_ROOT=""
RETAIN=7
DRY_RUN=false

require_value() {
  local flag="$1"
  if [ $# -lt 2 ] || [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
    echo "ERROR: $flag requires a value" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --retain)
      require_value "$1" "${2:-}"
      RETAIN="$2"
      shift 2
      ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: prune-backups.sh <dest-root> [--retain <N>] [--dry-run]"
      exit 0 ;;
    *)
      # first non-flag arg is dest-root
      if [ -z "$DEST_ROOT" ]; then
        DEST_ROOT="$1"
        shift
      else
        echo "ERROR: Unknown: $1" >&2
        exit 1
      fi
      ;;
  esac
done

[ -z "$DEST_ROOT" ] && { echo "ERROR: <dest-root> is required" >&2; exit 1; }
[ ! -d "$DEST_ROOT" ] && { echo "ERROR: Directory not found: $DEST_ROOT" >&2; exit 1; }
if ! echo "$RETAIN" | grep -qxE '[0-9]+' || [ "$RETAIN" -lt 1 ]; then
  echo "ERROR: --retain must be a positive integer (got: $RETAIN)" >&2
  exit 1
fi

TOTAL_REMOVED=0
TOTAL_SAVED=0

for HOST_DIR in "$DEST_ROOT"/*/; do
  [ -d "$HOST_DIR" ] || continue
  HOST=$(basename "$HOST_DIR")

  # Collect unique backup timestamp prefixes (YYYYMMDD-HHMMSS) from zip/tgz files
  # Sort descending so newest are kept
  TIMESTAMPS=$(find "$HOST_DIR" -maxdepth 1 -type f \( -name '*.zip' -o -name '*.tar.gz' \) \
    -print 2>/dev/null \
    | grep -oE '[0-9]{8}-[0-9]{6}' \
    | sort -r -u || true)

  TIMESTAMP_COUNT=$(printf "%s\n" "$TIMESTAMPS" | sed '/^$/d' | wc -l | tr -d ' ')

  if [ "$TIMESTAMP_COUNT" -le "$RETAIN" ]; then
    echo "  $HOST: $TIMESTAMP_COUNT sets (<= $RETAIN, nothing to prune)"
    TOTAL_SAVED=$((TOTAL_SAVED + TIMESTAMP_COUNT))
    continue
  fi

  # Keep first RETAIN (newest), remove the rest
  TO_REMOVE=$(echo "$TIMESTAMPS" | tail -n +$((RETAIN + 1)))

  REMOVED_COUNT=0

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
  done <<< "$TO_REMOVE"

  # Clean up .rsync-partial directories (rsync checkpoint artifacts from v3.5.0+)
  for pd in "$HOST_DIR"/.rsync-partial; do
    [ -d "$pd" ] || continue
    if $DRY_RUN; then
      echo "  [DRY-RUN] Would clean: .rsync-partial/"
    else
      rm -rf "$pd"
      echo "  Cleaned: .rsync-partial/"
    fi
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
  done

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
