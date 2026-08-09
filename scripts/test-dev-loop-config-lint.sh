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
workflow_selection: fixed
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
if (!codes.includes("workflow_fixed_profile_required")) throw new Error("workflow_fixed_profile_required");
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
workflow_selection: adaptive
workflow_capability: self-directed
workflow_risk: routine
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

WORKFLOW_BAD="$TMP/workflow-bad"
mkdir -p "$WORKFLOW_BAD/.claude"
cat > "$WORKFLOW_BAD/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: workflow-bad
release_branch: main
knowledge_layer: none
workflow_selection: adaptive
workflow_profile: full
workflow_capability: deepseek-flash
workflow_risk: critical
```
EOF
OUT_WORKFLOW_BAD="$(node "$LINT_JS" --repo "$WORKFLOW_BAD" --format json --no-write 2>/dev/null)" || true
echo "$OUT_WORKFLOW_BAD" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
const codes = j.findings.map((f) => f.code);
for (const code of ["workflow_adaptive_profile_conflict", "invalid_workflow_capability", "invalid_workflow_risk"]) {
  if (!codes.includes(code)) throw new Error(`${code}: ${JSON.stringify(j.findings)}`);
}
if (j.overall.state !== "blocked") throw new Error("invalid workflow config must block");
process.stdout.write("ok-workflow-policy\n");
'

WORKFLOW_TYPE_BAD="$TMP/workflow-type-bad"
mkdir -p "$WORKFLOW_TYPE_BAD/.claude"
cat > "$WORKFLOW_TYPE_BAD/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: workflow-type-bad
release_branch: main
knowledge_layer: none
workflow_selection: adaptive
workflow_profile: [full]
```
EOF
OUT_WORKFLOW_TYPE_BAD="$(node "$LINT_JS" --repo "$WORKFLOW_TYPE_BAD" --format json --no-write 2>/dev/null)" || true
echo "$OUT_WORKFLOW_TYPE_BAD" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
const typeFindings = j.findings.filter((item) => item.path === "workflow_profile");
if (typeFindings.length !== 1 || typeFindings[0].code !== "invalid_type") {
  throw new Error(`expected one parser-owned workflow_profile type finding: ${JSON.stringify(j.findings)}`);
}
if (j.findings.some((item) => item.code === "invalid_workflow_profile_type")) {
  throw new Error(`resolver duplicated parser type finding: ${JSON.stringify(j.findings)}`);
}
if (!Number.isInteger(typeFindings[0].line)) throw new Error("parser finding lost source line");
process.stdout.write("ok-workflow-type-dedup\n");
'

PIPELINE_BAD="$TMP/pipeline-bad"
mkdir -p "$PIPELINE_BAD/.claude"
cat > "$PIPELINE_BAD/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: pipeline-bad
release_branch: main
knowledge_layer: none
workflow_selection: adaptive
prd_pipeline: bogus
```
EOF
OUT_PIPELINE_BAD="$(node "$LINT_JS" --repo "$PIPELINE_BAD" --format json --no-write 2>/dev/null)" || true
echo "$OUT_PIPELINE_BAD" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
const matches = j.findings.filter((item) => item.code === "invalid_prd_pipeline");
if (matches.length !== 1) throw new Error(`expected one resolver-owned pipeline finding: ${JSON.stringify(j.findings)}`);
if (j.overall.state !== "blocked") throw new Error("invalid pipeline must block");
process.stdout.write("ok-workflow-pipeline\n");
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

# Prefer the local config when present (developer workspaces). CI checkouts only
# have the committed example, so stage that under a temp repo whose scripts/
# tree links back to the real suite paths for e2e existence checks.
HEALTHY_REPO="$TMP/healthy-repo"
mkdir -p "$HEALTHY_REPO/.claude" "$HEALTHY_REPO/skills/dev-loop/templates"
if [[ -f "$ROOT/.claude/dev-loop.config.md" ]]; then
  cp "$ROOT/.claude/dev-loop.config.md" "$HEALTHY_REPO/.claude/dev-loop.config.md"
else
  cp "$ROOT/.claude/dev-loop.config.example.md" "$HEALTHY_REPO/.claude/dev-loop.config.md"
fi
cp "$ROOT/skills/dev-loop/templates/project-config.md" \
  "$HEALTHY_REPO/skills/dev-loop/templates/project-config.md"
ln -s "$ROOT/scripts" "$HEALTHY_REPO/scripts"
OUT2="$(node "$LINT_JS" --repo "$HEALTHY_REPO" --format json --no-write 2>/dev/null)" ||
  fail "healthy config lint failed"
echo "$OUT2" | node -e '
const j=JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.overall.state !== "healthy") throw new Error("agent-skills config should be healthy: "+JSON.stringify(j.findings));
process.stdout.write("ok-healthy\n");
'

printf 'test-dev-loop-config-lint: all checks passed\n'
