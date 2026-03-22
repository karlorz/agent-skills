#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  schedule-remove.sh --job-id ID [--purge-logs] [--dry-run] [--json]
  schedule-remove.sh ID [--purge-logs] [--dry-run] [--json]
EOF
}

JOB_ID=""
PURGE_LOGS=false
DRY_RUN=false
JSON_OUTPUT=false

while (($# > 0)); do
  case "$1" in
    --job-id)
      shift
      loop_require_value "--job-id" "${1:-}"
      JOB_ID="$1"
      ;;
    --purge-logs)
      PURGE_LOGS=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --json)
      JSON_OUTPUT=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$JOB_ID" ]]; then
        JOB_ID="$1"
      else
        loop_error "Unknown argument: $1"
      fi
      ;;
  esac
  shift || true
done

if [[ -z "$JOB_ID" ]]; then
  usage >&2
  exit 1
fi

loop_init_registry

if ! JOB_JSON="$(loop_get_job_json "$JOB_ID" 2>/dev/null)"; then
  loop_error "No scheduled loop job found for id: $JOB_ID"
fi

PLIST_PATH="$(jq -r '.plist_path // empty' <<<"$JOB_JSON")"
LOG_PATH="$(jq -r '.log_path // empty' <<<"$JOB_JSON")"
ERROR_LOG_PATH="$(jq -r '.error_log_path // empty' <<<"$JOB_JSON")"

if ! $DRY_RUN; then
  if [[ -n "$PLIST_PATH" && -f "$PLIST_PATH" ]]; then
    loop_unregister_launchd_job "$PLIST_PATH"
    rm -f "$PLIST_PATH"
  fi

  loop_remove_job_from_registry "$JOB_ID"

  if $PURGE_LOGS; then
    rm -f "$LOG_PATH" "$ERROR_LOG_PATH"
  fi
fi

if $JSON_OUTPUT; then
  jq -n \
    --argjson job "$JOB_JSON" \
    --argjson purge_logs "$($PURGE_LOGS && printf 'true' || printf 'false')" \
    --arg mode "$($DRY_RUN && printf 'dry-run' || printf 'live')" \
    '{mode: $mode, purge_logs: $purge_logs, removed: $job}'
  exit 0
fi

echo "Removed loop job: $JOB_ID"
if $PURGE_LOGS; then
  echo "Logs purged."
else
  echo "Logs retained."
fi
if $DRY_RUN; then
  echo "Mode: dry-run"
fi
