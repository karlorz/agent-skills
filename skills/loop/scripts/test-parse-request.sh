#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse-request.py"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

parse() {
  python3 "$PARSER" --request "$1"
}

json="$(parse '5m /babysit-prs')"
assert_eq "add" "$(jq -r '.action' <<<"$json")" "leading interval action"
assert_eq "leading_interval" "$(jq -r '.parse_mode' <<<"$json")" "leading interval parse mode"
assert_eq "5m" "$(jq -r '.interval' <<<"$json")" "leading interval value"
assert_eq "/babysit-prs" "$(jq -r '.prompt' <<<"$json")" "leading interval prompt"

json="$(parse 'check the deploy every 20m')"
assert_eq "add" "$(jq -r '.action' <<<"$json")" "trailing every action"
assert_eq "trailing_every" "$(jq -r '.parse_mode' <<<"$json")" "trailing every parse mode"
assert_eq "20m" "$(jq -r '.interval' <<<"$json")" "trailing every interval"
assert_eq "check the deploy" "$(jq -r '.prompt' <<<"$json")" "trailing every prompt"

json="$(parse 'run tests every 5 minutes')"
assert_eq "5m" "$(jq -r '.interval' <<<"$json")" "word interval normalization"
assert_eq "run tests" "$(jq -r '.prompt' <<<"$json")" "word interval prompt"

json="$(parse 'check every PR')"
assert_eq "default_interval" "$(jq -r '.parse_mode' <<<"$json")" "default interval parse mode"
assert_eq "10m" "$(jq -r '.interval' <<<"$json")" "default interval value"
assert_eq "check every PR" "$(jq -r '.prompt' <<<"$json")" "default interval prompt"

json="$(parse 'status.')"
assert_eq "status" "$(jq -r '.action' <<<"$json")" "status action"

json="$(parse 'remove loop-1234567890-abcdef')"
assert_eq "remove" "$(jq -r '.action' <<<"$json")" "remove action"
assert_eq "loop-1234567890-abcdef" "$(jq -r '.job_id' <<<"$json")" "remove job id"

json="$(parse 'show logs for loop-1234567890-abcdef')"
assert_eq "logs" "$(jq -r '.action' <<<"$json")" "logs action"
assert_eq "loop-1234567890-abcdef" "$(jq -r '.job_id' <<<"$json")" "logs job id"

json="$(parse 'Create a recurring loop job in the current workspace with interval 10m and prompt "check the deploy". Use dry-run and do not run now.')"
assert_eq "add" "$(jq -r '.action' <<<"$json")" "explicit field action"
assert_eq "explicit_fields" "$(jq -r '.parse_mode' <<<"$json")" "explicit field parse mode"
assert_eq "10m" "$(jq -r '.interval' <<<"$json")" "explicit field interval"
assert_eq "check the deploy" "$(jq -r '.prompt' <<<"$json")" "explicit field prompt"
assert_eq "true" "$(jq -r '.dry_run' <<<"$json")" "dry-run modifier"
assert_eq "false" "$(jq -r '.run_now' <<<"$json")" "run-now suppression"

echo "8/8 parser assertions passed"
