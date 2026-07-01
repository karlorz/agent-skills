#!/usr/bin/env bash
# PRD alias: e2e-dev-loop-status.sh → test-dev-loop-status.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT/scripts/test-dev-loop-status.sh" "$@"