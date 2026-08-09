#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/skills/dev-loop/scripts/dev-loop-workflow-profile.js"

fail() {
  printf 'test-dev-loop-workflow-profile: %s\n' "$1" >&2
  exit 1
}

[[ -f "$RESOLVER" ]] || fail "missing skills/dev-loop/scripts/dev-loop-workflow-profile.js"

node - "$RESOLVER" <<'NODE'
"use strict";

const assert = require("node:assert/strict");
const resolverPath = process.argv[2];
const {
  PIPELINE_STEPS,
  PRD_PIPELINES,
  WORKFLOW_CAPABILITIES,
  WORKFLOW_MODES,
  WORKFLOW_PROFILES,
  WORKFLOW_RISKS,
  pipelineSteps,
  resolveWorkflowProfile,
} = require(resolverPath);

assert.deepEqual([...WORKFLOW_PROFILES], ["native", "guided", "full"]);
assert.deepEqual([...WORKFLOW_MODES], ["fixed", "adaptive"]);
assert.deepEqual([...WORKFLOW_CAPABILITIES], ["self-directed", "needs-guidance", "unknown"]);
assert.deepEqual([...WORKFLOW_RISKS], ["routine", "elevated"]);
assert.deepEqual([...PRD_PIPELINES], ["full", "tdd-first", "single-pass", "debug-only", "manual"]);
assert.deepEqual(pipelineSteps("guided-does-not-exist"), []);
assert.deepEqual(pipelineSteps("tdd-first"), ["plan", "execute", "review", "merge"]);
assert.deepEqual(PIPELINE_STEPS.full, ["spec", "plan", "execute", "review", "merge", "save"]);

function resolved(input, expected) {
  const actual = resolveWorkflowProfile(input);
  assert.equal(actual.ok, true, JSON.stringify(actual));
  assert.equal(actual.unresolved, false, JSON.stringify(actual));
  assert.equal(actual.prompts, false, JSON.stringify(actual));
  for (const [key, value] of Object.entries(expected)) {
    assert.deepEqual(actual[key], value, `${key}: ${JSON.stringify(actual)}`);
  }
  return actual;
}

function unresolved(input, code) {
  const actual = resolveWorkflowProfile(input);
  assert.equal(actual.ok, false, JSON.stringify(actual));
  assert.equal(actual.unresolved, true, JSON.stringify(actual));
  assert.equal(actual.profile, null, JSON.stringify(actual));
  assert.equal(actual.prompts, false, JSON.stringify(actual));
  assert.ok(actual.diagnostics.some((item) => item.code === code), JSON.stringify(actual));
  return actual;
}

resolved({}, {
  profile: "native",
  mode: "adaptive",
  authority: "builtin_adaptive",
  explicit: false,
  defaultPipeline: "single-pass",
  effectivePipeline: "single-pass",
});

resolved(
  {
    availabilityEvidence: ["superpowers:brainstorming", "superpowers:writing-plans"],
    model: "frontier-product-name-must-not-select-policy",
  },
  {
    profile: "native",
    mode: "adaptive",
    authority: "builtin_adaptive",
    explicit: false,
  },
);

resolved(
  { authorities: { project: { mode: "fixed", profile: "full" } } },
  {
    profile: "full",
    mode: "fixed",
    authority: "project",
    explicit: true,
    defaultPipeline: "full",
    effectivePipeline: "full",
  },
);

resolved(
  {
    authorities: {
      user: { mode: "fixed", profile: "native" },
      work_item: { mode: "fixed", profile: "full" },
      project: { mode: "fixed", profile: "guided" },
      user_default: { mode: "fixed", profile: "full" },
    },
  },
  { profile: "native", authority: "user" },
);

resolved(
  {
    authorities: {
      work_item: { mode: "fixed", profile: "guided" },
      project: { mode: "fixed", profile: "full" },
    },
  },
  { profile: "guided", authority: "work_item" },
);

resolved(
  {
    authorities: {
      project: { mode: "adaptive", capability: "needs-guidance", risk: "routine" },
      user_default: { mode: "fixed", profile: "native" },
    },
  },
  {
    profile: "guided",
    mode: "adaptive",
    authority: "project",
    explicit: false,
    defaultPipeline: "tdd-first",
  },
);

resolved(
  { taskEvidence: { risk: "elevated" }, capabilityEvidence: "self-directed" },
  { profile: "guided", authority: "builtin_adaptive" },
);

resolved(
  {
    authorities: {
      user_default: { mode: "fixed", profile: "guided" },
    },
    sessionKind: "goal",
  },
  { profile: "guided", authority: "user_default", sessionKind: "goal" },
);

for (const sessionKind of ["headless", "goal", "satellite", "ci"]) {
  const result = resolved({ sessionKind }, { profile: "native", sessionKind });
  assert.equal(result.prompts, false);
}

unresolved(
  { authorities: { project: { mode: "fixed" } } },
  "workflow_fixed_profile_required",
);
unresolved(
  { authorities: { project: { mode: "adaptive", profile: "full" } } },
  "workflow_adaptive_profile_conflict",
);
unresolved(
  { authorities: { project: { mode: "automatic" } } },
  "invalid_workflow_selection",
);
unresolved(
  { authorities: { project: { mode: "fixed", profile: "strict" } } },
  "invalid_workflow_profile",
);
unresolved(
  { authorities: { project: { mode: "adaptive", capability: "deepseek-flash" } } },
  "invalid_workflow_capability",
);
unresolved(
  { authorities: { project: { mode: "adaptive", risk: "critical" } } },
  "invalid_workflow_risk",
);
unresolved(
  { configurationErrors: [{ code: "malformed_yaml", message: "bad YAML" }] },
  "workflow_configuration_invalid",
);
unresolved(
  {
    authorities: { project: { mode: "adaptive" } },
    legacy: { prdPipeline: "bogus" },
  },
  "invalid_prd_pipeline",
);

resolved(
  { legacy: { prdPipeline: "full" } },
  {
    profile: "full",
    mode: "fixed",
    authority: "project_legacy",
    explicit: true,
    defaultPipeline: "full",
  },
);
resolved(
  { legacy: { prdPipeline: "tdd-first" } },
  { profile: "guided", authority: "project_legacy", defaultPipeline: "tdd-first" },
);
for (const prdPipeline of ["single-pass", "debug-only", "manual"]) {
  resolved(
    { legacy: { prdPipeline } },
    { profile: "native", authority: "project_legacy" },
  );
}
resolved(
  { availabilityEvidence: ["superpowers"] },
  { profile: "native", authority: "builtin_adaptive", explicit: false },
);

resolved(
  {
    authorities: { project: { mode: "fixed", profile: "native" } },
    legacy: { prdPipeline: "full" },
  },
  { profile: "native", authority: "project", effectivePipeline: "full" },
);

process.stdout.write("test-dev-loop-workflow-profile: all checks passed\n");
NODE

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/config.md" <<'EOF'
```yaml
workflow_selection: adaptive
workflow_capability: needs-guidance
workflow_risk: routine
prd_layer: tdd
```
EOF

CLI_OUT="$(node "$RESOLVER" --config "$TMP/config.md" --session-kind goal)" ||
  fail "resolver CLI failed"
echo "$CLI_OUT" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.schema_version !== "dev-loop-workflow-profile.v1" || j.read_only !== true) throw new Error(JSON.stringify(j));
if (j.workflow_profile.profile !== "guided" || j.workflow_profile.sessionKind !== "goal") throw new Error(JSON.stringify(j));
if (j.prd_layer !== "tdd" || j.prd_pipeline !== "tdd-first") throw new Error(JSON.stringify(j));
'
