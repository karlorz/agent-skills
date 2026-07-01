#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASH="$ROOT/skills/dev-loop/scripts/dev-loop-dashboard.js"
fail() { printf 'test-dev-loop-dashboard: %s\n' "$1" >&2; exit 1; }
[[ -f "$DASH" ]] || fail "missing dashboard script"
OUT="$(node "$DASH" --repo "$ROOT" --format json --no-write --refresh --project agent-skills 2>/dev/null)" || fail "dashboard failed"
echo "$OUT" | node -e '
const j = JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-dashboard.v1") throw new Error("schema");
if (j.read_only !== true) throw new Error("read_only");
if (!Array.isArray(j.slices) || j.slices.length < 4) throw new Error("slices");
const ids = new Set(j.slices.map((s) => s.id));
for (const id of ["status", "config_lint", "config_migrate", "doctor_hud"]) {
  if (!ids.has(id)) throw new Error("missing slice "+id);
}
process.stdout.write("ok-dashboard\n");
'
printf 'test-dev-loop-dashboard: all checks passed\n'