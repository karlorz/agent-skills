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
merge_policy:
  strategy: unsafe-direct
  auto_merge: true
  merge_method: fast-forward
  require_work_item_approval: false
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
if (!codes.includes("invalid_merge_strategy")) throw new Error("merge_strategy");
if (!codes.includes("invalid_merge_method")) throw new Error("merge_method");
if (!codes.includes("auto_merge_requires_work_item_approval")) throw new Error("merge_approval");
process.stdout.write("ok-bad-config\n");
'

VALID="$TMP/valid"
mkdir -p "$VALID/.claude"
cat > "$VALID/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: valid
release_branch: main
prd_layer: manual
knowledge_layer: none
merge_policy:
  strategy: repo-policy
  auto_merge: false
  merge_method: squash
  require_work_item_approval: true
```
EOF

OUT_VALID="$(node "$LINT_JS" --repo "$VALID" --format json --no-write 2>/dev/null)" || true
echo "$OUT_VALID" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
const codes = j.findings.map((f) => f.code);
if (codes.includes("invalid_merge_strategy")) throw new Error("repo-policy must be accepted");
process.stdout.write("ok-merge-policy\n");
'

SCHEMA_BAD="$TMP/schema-bad"
mkdir -p "$SCHEMA_BAD/.claude"
cat > "$SCHEMA_BAD/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: schema-bad
release_branch: main
knowledge_layer: none
merge_policy:
  unknown_nested: true
```
EOF
OUT_SCHEMA_BAD="$(node "$LINT_JS" --repo "$SCHEMA_BAD" --format json --no-write 2>/dev/null)" || true
echo "$OUT_SCHEMA_BAD" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
const finding = (j.findings || []).find((item) => item.code === "unknown_key" && item.path === "merge_policy.unknown_nested");
if (!finding) throw new Error(`schema unknown-key finding missing: ${JSON.stringify(j.findings)}`);
if (!Number.isInteger(finding.line)) throw new Error(`schema finding lost source line: ${JSON.stringify(finding)}`);
process.stdout.write("ok-schema-diagnostics\n");
'

OUT_SCHEMA_UNAVAILABLE="$(DEV_LOOP_CONFIG_PYTHON=/definitely/missing/python node "$LINT_JS" --repo "$SCHEMA_BAD" --format json --no-write 2>/dev/null)" || true
echo "$OUT_SCHEMA_UNAVAILABLE" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (!(j.findings || []).some((item) => item.code === "parser_unavailable")) {
  throw new Error(`parser-unavailable finding missing: ${JSON.stringify(j.findings)}`);
}
if (j.overall.state !== "blocked") throw new Error("parser-unavailable config must be blocked");
process.stdout.write("ok-schema-capability-error\n");
'

mkdir -p "$ROOT/.claude"
OUT2="$(node "$LINT_JS" --repo "$ROOT" --format json --no-write 2>/dev/null)" || fail "real config lint failed"
echo "$OUT2" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.overall.state !== "healthy") throw new Error("agent-skills config should be healthy: "+JSON.stringify(j.findings));
process.stdout.write("ok-healthy\n");
'

printf 'test-dev-loop-config-lint: all checks passed\n'
