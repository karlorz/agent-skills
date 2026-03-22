#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  schedule-list.sh [--json]
EOF
}

JSON_OUTPUT=false

while (($# > 0)); do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      loop_error "Unknown argument: $1"
      ;;
  esac
  shift || true
done

loop_init_registry

if $JSON_OUTPUT; then
  loop_list_jobs_json
  exit 0
fi

JOB_COUNT="$(loop_job_count)"
if [[ "$JOB_COUNT" == "0" ]]; then
  echo "No loop jobs scheduled."
  exit 0
fi

printf '%-24s %-8s %-10s %-8s %s\n' "JOB ID" "INTERVAL" "STATUS" "RUNS" "PROMPT"
loop_list_jobs_json \
  | jq -r '.[] | [.id, .interval, (.last_status // "scheduled"), ((.run_count // 0) | tostring), .prompt] | @tsv' \
  | while IFS=$'\t' read -r job_id interval status run_count prompt; do
      printf '%-24s %-8s %-10s %-8s %s\n' "$job_id" "$interval" "$status" "$run_count" "$prompt"
    done
