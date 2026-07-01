#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/skills/dev-loop/scripts/dev-loop-why-skipped.js"
chmod +x "$JS" 2>/dev/null || true
VAULT="${VAULT:-$HOME/wiki}"
WORK="2026-07-01-dev-loop-why-skipped-cli"
OUT="$(node "$JS" --project agent-skills --work "$WORK" --vault "$VAULT" --repo "$ROOT" --json 2>/dev/null)" || true
echo "$OUT" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-why-skipped.v1") throw new Error("schema");
if (j.unattended_ready === true && j.missing_readiness.length === 0) {
  console.log("ok-ready-slug");
} else if (j.unattended_ready === false && j.missing_readiness.length > 0) {
  console.log("ok-not-ready-slug");
} else throw new Error("unexpected readiness state");
'
printf 'test-dev-loop-why-skipped: passed\n'