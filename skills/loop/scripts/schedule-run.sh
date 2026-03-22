#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  schedule-run.sh --job-id ID [--trigger manual|scheduled] [--dry-run] [--json]
  schedule-run.sh ID [--trigger manual|scheduled] [--dry-run] [--json]
EOF
}

JOB_ID=""
TRIGGER="manual"
DRY_RUN=false
JSON_OUTPUT=false

while (($# > 0)); do
  case "$1" in
    --job-id)
      shift
      loop_require_value "--job-id" "${1:-}"
      JOB_ID="$1"
      ;;
    --trigger)
      shift
      loop_require_value "--trigger" "${1:-}"
      TRIGGER="$1"
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

WORKSPACE="$(jq -r '.workspace' <<<"$JOB_JSON")"
PROMPT="$(jq -r '.prompt' <<<"$JOB_JSON")"
COMMAND_STRING="$(loop_build_codex_command "$WORKSPACE" "$PROMPT")"

if $DRY_RUN; then
  if $JSON_OUTPUT; then
    jq -n \
      --arg job_id "$JOB_ID" \
      --arg trigger "$TRIGGER" \
      --arg command "$COMMAND_STRING" \
      '{mode: "dry-run", job_id: $job_id, trigger: $trigger, command: $command}'
  else
    echo "Dry-run command for $JOB_ID:"
    echo "$COMMAND_STRING"
  fi
  exit 0
fi

set +e
bash "$SCRIPT_DIR/job-runner.sh" --job-id "$JOB_ID" --trigger "$TRIGGER"
EXIT_CODE=$?
set -e

UPDATED_JOB_JSON="$(loop_get_job_json "$JOB_ID")"

if $JSON_OUTPUT; then
  jq -n \
    --argjson job "$UPDATED_JOB_JSON" \
    --argjson exit_code "$EXIT_CODE" \
    '{mode: "live", exit_code: $exit_code, job: $job}'
  exit 0
fi

echo "Ran loop job: $JOB_ID"
echo "Exit code: $EXIT_CODE"
echo "Status: $(jq -r '.last_status' <<<"$UPDATED_JOB_JSON")"
echo "Logs: $(jq -r '.log_path' <<<"$UPDATED_JOB_JSON")"
echo "Errors: $(jq -r '.error_log_path' <<<"$UPDATED_JOB_JSON")"
exit "$EXIT_CODE"
