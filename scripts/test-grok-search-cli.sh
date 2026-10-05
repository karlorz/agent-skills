#!/usr/bin/env bash
# Behaviour and contract test suite for grok-search Skill+CLI M1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/grok-search/test-cli.js"

if [[ ! -f "$FIXTURE" ]]; then
  echo "missing fixture test: $FIXTURE" >&2
  exit 1
fi

node --test "$FIXTURE"
printf 'test-grok-search-cli: all checks passed\n'
