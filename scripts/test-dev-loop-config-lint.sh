#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT_JS="$ROOT/skills/dev-loop/scripts/dev-loop-config-lint.js"

fail() { printf 'test-dev-loop-config-lint: %s\n' "$1" >&2; exit 1; }

[[ -f "$LINT_JS" ]] || fail "missing dev-loop-config-lint.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: bad
release_branch: main
prd_layer: not-a-layer
knowledge_layer: skillwiki
release_policy:
  auto_bump: true
```
EOF

OUT="$(node "$LINT_JS" --repo "$TMP" --format json --no-write 2>/dev/null)" || true
echo "$OUT" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-config-lint.v1") throw new Error("schema");
if (j.read_only !== true) throw new Error("read_only");
if (j.overall.state !== "blocked") throw new Error("expected blocked");
const codes = j.findings.map((f) => f.code);
if (!codes.includes("invalid_prd_layer")) throw new Error("prd_layer");
if (!codes.includes("auto_bump_no_triggers")) throw new Error("triggers");
process.stdout.write("ok-bad-config\n");
'

mkdir -p "$ROOT/.claude"
OUT2="$(node "$LINT_JS" --repo "$ROOT" --format json --no-write 2>/dev/null)" || fail "real config lint failed"
echo "$OUT2" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.overall.state !== "healthy") throw new Error("agent-skills config should be healthy: "+JSON.stringify(j.findings));
process.stdout.write("ok-healthy\n");
'

printf 'test-dev-loop-config-lint: all checks passed\n'