#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_JS="$ROOT/skills/dev-loop/scripts/dev-loop-status.js"

fail() {
  printf 'test-dev-loop-status: %s\n' "$1" >&2
  exit 1
}

[[ -f "$STATUS_JS" ]] || fail "missing dev-loop-status.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
# test

```yaml
slug: test-none
release_branch: main
knowledge_layer: none
prd_layer: manual
publish_via: none
```
EOF

git -C "$TMP" init -q
git -C "$TMP" config user.email "test@test"
git -C "$TMP" config user.name "test"
echo x > "$TMP/README.md"
git -C "$TMP" add README.md
git -C "$TMP" commit -q -m "init"
git -C "$TMP" branch -M main

OUT="$(node "$STATUS_JS" --repo "$TMP" --project test-none --format json --no-write 2>/dev/null)" || fail "status script failed on none layer"

echo "$OUT" | node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(0, "utf8"));
if (j.schema_version !== "dev-loop-status.v1") throw new Error("bad schema");
if (j.read_only !== true || j.writes_executed !== false) throw new Error("read_only contract");
if (j.project.slug !== "test-none") throw new Error("slug");
if (j.pipeline_preview.merge.strategy !== "repo-policy") throw new Error("repo-policy must be canonical");
if (j.pipeline_preview.merge.auto_merge_configured !== false) throw new Error("auto merge must default off");
if (j.pipeline_preview.merge.auto_merge_eligible !== false) throw new Error("auto merge must fail closed");
if ((j.pipeline_preview.merge.failed_gates || []).includes("ci_configured")) throw new Error("CI configuration is not merge authority");
process.stdout.write("ok-none-layer\n");
'

cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
---
name: status merge fixture
---

```yaml
slug: test-merged
release_branch: main
knowledge_layer: none
prd_layer: manual
merge_policy:
  strategy: pull-request
  auto_merge: true
  merge_method: rebase
  require_work_item_approval: true
```

```yaml
merge_policy:
  auto_merge: false
```
EOF
OUT_MERGED="$(node "$STATUS_JS" --repo "$TMP" --project test-merged --format json --no-write 2>/dev/null)" || fail "status failed on deep-merged config"
echo "$OUT_MERGED" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
const merge = j.pipeline_preview.merge;
if (merge.strategy !== "pull-request" || merge.merge_method !== "rebase") throw new Error(`nested fields lost: ${JSON.stringify(merge)}`);
if (merge.auto_merge_configured !== false) throw new Error(`later scalar did not win: ${JSON.stringify(merge)}`);
process.stdout.write("ok-deep-merged-config\n");
'

cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: test-invalid
release_branch: main
knowledge_layer: none
merge_policy:
  strategy: pull-request
  unknown_nested: true
```
EOF
set +e
OUT_INVALID="$(node "$STATUS_JS" --repo "$TMP" --project test-invalid --format json --no-write 2>/dev/null)"
INVALID_EXIT=$?
set -e
[[ "$INVALID_EXIT" -eq 1 ]] || fail "schema-invalid status must exit 1, got $INVALID_EXIT"
echo "$OUT_INVALID" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.health.state !== "blocked" || !j.blockers.some((item) => item.code === "invalid_config")) throw new Error(`schema error must block: ${JSON.stringify(j)}`);
if (!(j.health.config_parser?.errors || []).some((item) => item.path === "merge_policy.unknown_nested")) throw new Error("schema path missing from health");
if (j.pipeline_preview.merge.strategy !== "repo-policy") throw new Error("status consumed config after schema failure");
process.stdout.write("ok-schema-blocker\n");
'

set +e
OUT_PARSER_MISSING="$(DEV_LOOP_CONFIG_PYTHON=/definitely/missing/python node "$STATUS_JS" --repo "$TMP" --project test-invalid --format json --no-write 2>/dev/null)"
PARSER_MISSING_EXIT=$?
set -e
[[ "$PARSER_MISSING_EXIT" -eq 1 ]] || fail "parser-unavailable status must exit 1, got $PARSER_MISSING_EXIT"
echo "$OUT_PARSER_MISSING" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (!(j.health.config_parser?.errors || []).some((item) => item.code === "parser_unavailable")) throw new Error("parser capability error missing");
process.stdout.write("ok-parser-capability-blocker\n");
'

cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: test-release
release_branch: main
knowledge_layer: none
prd_layer: manual
publish_via: ci-tag-trigger
release_policy:
  auto_bump: true
  trigger_globs:
    - "src/**"
  skip_globs:
    - "*.md"
```
EOF
git -C "$TMP" tag v0.0.1
mkdir -p "$TMP/src"
echo changed > "$TMP/src/changed.js"
git -C "$TMP" add src/changed.js
git -C "$TMP" commit -q -m "change after tag"

OUT_RELEASE="$(node "$STATUS_JS" --repo "$TMP" --project test-release --format json --no-write 2>/dev/null)" || fail "status script failed on post-tag release preview"
echo "$OUT_RELEASE" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.pipeline_preview.release.would_publish !== true) {
  throw new Error(`expected matching post-tag change to trigger release: ${JSON.stringify(j.pipeline_preview.release)}`);
}
if (!(j.pipeline_preview.release.matched_files || []).includes("src/changed.js")) {
  throw new Error(`expected changed path in release preview: ${JSON.stringify(j.pipeline_preview.release)}`);
}
process.stdout.write("ok-release-preview\n");
'

NESTED_REPO="$TMP/nested-repo"
NESTED_HOME="$TMP/nested-home"
mkdir -p "$NESTED_REPO/.claude"
mkdir -p "$NESTED_REPO/skills/dev-loop/.claude-plugin"
mkdir -p "$NESTED_REPO/skills/dev-loop/agents"
mkdir -p "$NESTED_REPO/skills/dev-loop/skills/dev-loop"
mkdir -p "$NESTED_HOME/.codex/plugins/cache/karlorz-agent-skills/dev-loop/9.8.7/skills/dev-loop"
mkdir -p "$NESTED_HOME/.codex/plugins/cache/karlorz-agent-skills/playwright-cli/1.2.3/agents"
cp "$TMP/.claude/dev-loop.config.md" "$NESTED_REPO/.claude/dev-loop.config.md"
cat > "$NESTED_REPO/skills/dev-loop/.claude-plugin/plugin.json" <<'EOF'
{"name":"dev-loop","version":"9.8.7"}
EOF
cat > "$NESTED_REPO/skills/dev-loop/skills/dev-loop/SKILL.md" <<'EOF'
---
name: dev-loop
---
# nested source
EOF
cp "$NESTED_REPO/skills/dev-loop/skills/dev-loop/SKILL.md" \
  "$NESTED_HOME/.codex/plugins/cache/karlorz-agent-skills/dev-loop/9.8.7/skills/dev-loop/SKILL.md"
cat > "$NESTED_REPO/skills/dev-loop/agents/research.md" <<'EOF'
---
name: research-worker
---
EOF
cat > "$NESTED_HOME/.codex/plugins/cache/karlorz-agent-skills/playwright-cli/1.2.3/agents/browser-worker.md" <<'EOF'
---
name: browser-worker
---
EOF
cat > "$NESTED_REPO/skills/dev-loop/dependencies.yaml" <<'EOF'
optional:
  - kind: agent
    ref: dev-loop:research-worker
    capability: research_scan
    used_by: ["IDLE step 4"]
  - kind: agent
    ref: playwright-cli:browser-worker
    capability: browser_verify
    used_by: ["BROWSER-VERIFY step 6a"]
  - kind: agent
    ref: missing:browser-worker
    capability: browser_verify
    used_by: ["BROWSER-VERIFY step 6a"]
EOF

OUT_NESTED="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$NESTED_REPO" --project test-none --format json --no-write 2>/dev/null)" || fail "nested-layout status failed"
echo "$OUT_NESTED" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.health.skill_cache.state !== "in_sync") {
  throw new Error(`nested source/cache should be in_sync, got ${JSON.stringify(j.health.skill_cache)}`);
}
if (!j.health.skill_cache.cache_path.endsWith("/skills/dev-loop/SKILL.md")) {
  throw new Error(`unexpected nested cache path: ${j.health.skill_cache.cache_path}`);
}
const missing = j.health.missing_optional;
if (missing.includes("dev-loop:research-worker")) throw new Error("self agent false negative");
if (missing.includes("playwright-cli:browser-worker")) throw new Error("cached agent false negative");
if (!missing.includes("missing:browser-worker")) throw new Error("genuine missing agent not reported");
if (j.health.dep_status !== "degraded") throw new Error("genuine optional miss must degrade");
if (j.health.state !== "healthy") throw new Error(`irrelevant optional miss must not degrade health: ${JSON.stringify(j.health)}`);
if ((j.health.relevant_missing_optional || []).length !== 0) throw new Error("irrelevant optional miss classified relevant");
if ((j.health.reasons || []).length !== 0) throw new Error("healthy state must have no reasons");
if (j.lifecycle?.state !== "idle" || j.lifecycle?.next_action !== "idle") {
  throw new Error(`expected independent idle lifecycle: ${JSON.stringify(j.lifecycle)}`);
}
if (j.overall.state !== j.health.state || j.overall.next_action !== j.lifecycle.next_action) {
  throw new Error("overall must project health and lifecycle");
}
process.stdout.write("ok-nested-cache\n");
'

cat > "$NESTED_REPO/skills/dev-loop/dependencies.yaml" <<'EOF'
optional:
  - kind: agent
    ref: missing:research-worker
    capability: research_scan
    used_by: ["IDLE step 4"]
EOF

OUT_RELEVANT="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$NESTED_REPO" --project test-none --format json --no-write 2>/dev/null)" || fail "relevant optional status failed"
echo "$OUT_RELEVANT" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.health.state !== "degraded") throw new Error(`relevant optional miss must degrade: ${JSON.stringify(j.health)}`);
if (!(j.health.relevant_missing_optional || []).includes("missing:research-worker")) {
  throw new Error("relevant optional dependency not classified");
}
const reason = (j.health.reasons || []).find((item) => item.code === "missing_relevant_optional_deps");
if (!reason || reason.severity !== "degraded" || !reason.detail.includes("missing:research-worker")) {
  throw new Error(`missing structured degradation reason: ${JSON.stringify(j.health.reasons)}`);
}
if (j.lifecycle?.state !== "idle" || j.lifecycle?.next_action !== "idle") {
  throw new Error("health degradation must not change idle lifecycle");
}
process.stdout.write("ok-relevant-optional\n");
'

OUT_STATUS_MODE="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$NESTED_REPO" --project test-none --preview-mode status --format json --no-write 2>/dev/null)" || fail "explicit status preview failed"
echo "$OUT_STATUS_MODE" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.lifecycle?.state !== "active" || j.lifecycle?.next_action !== "status") {
  throw new Error(`explicit preview must be active: ${JSON.stringify(j.lifecycle)}`);
}
if (!j.lifecycle.reason.includes("status")) throw new Error(`lifecycle reason must name requested action: ${j.lifecycle.reason}`);
process.stdout.write("ok-explicit-lifecycle\n");
'

OUT_MARKDOWN="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$NESTED_REPO" --project test-none --format markdown --no-write 2>/dev/null)" || fail "markdown status failed"
grep -q -- "- Health state: \*\*degraded\*\*" <<<"$OUT_MARKDOWN" || fail "markdown missing independent health state"
grep -q -- "- Lifecycle state: \*\*idle\*\*" <<<"$OUT_MARKDOWN" || fail "markdown missing independent lifecycle state"

cat > "$NESTED_REPO/skills/dev-loop/dependencies.yaml" <<'EOF'
required:
  - kind: skill
    ref: missing:required-skill
    capability: create_work_item
    used_by: ["WORK step 2"]
optional: []
EOF

set +e
OUT_BLOCKED="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$NESTED_REPO" --project test-none --format json --no-write 2>/dev/null)"
BLOCKED_EXIT=$?
set -e
[[ "$BLOCKED_EXIT" -eq 1 ]] || fail "blocked status must exit 1, got $BLOCKED_EXIT"
echo "$OUT_BLOCKED" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.health.state !== "blocked") throw new Error(`required miss must block health: ${JSON.stringify(j.health)}`);
if (j.lifecycle?.state !== "active" || j.lifecycle?.next_action !== "blocked") {
  throw new Error(`blocked operation must retain active lifecycle: ${JSON.stringify(j.lifecycle)}`);
}
if (j.overall.state !== "blocked" || j.overall.next_action !== "blocked" || j.overall.reason !== j.health.reasons[0].detail) {
  throw new Error("blocked overall projection mismatch");
}
process.stdout.write("ok-blocked-lifecycle\n");
'

VAULT="$TMP/wiki"
mkdir -p "$VAULT/projects/agent-skills/work/2026-07-01-ready"
mkdir -p "$VAULT/projects/agent-skills/work/2026-07-01-skip"
cat > "$VAULT/SCHEMA.md" <<'EOF'
# schema
## Layers
- `concepts/`
EOF

cat > "$VAULT/projects/agent-skills/work/2026-07-01-ready/spec.md" <<'EOF'
---
title: Ready item
status: planned
automation_ready: true
human_questions_resolved: true
spec_preflight_approved: true
plan_preflight_approved: true
preflight_state: ready
merge_auto_approved: true
---
EOF

cat > "$VAULT/projects/agent-skills/work/2026-07-01-skip/spec.md" <<'EOF'
---
title: Skip item
status: planned
---
EOF

mkdir -p "$TMP/skills/dev-loop"
cat > "$TMP/skills/dev-loop/dependencies.yaml" <<'EOF'
optional:
  - kind: agent
    ref: codex:codex-rescue
    capability: codex_code_review_backend
    used_by: ["REVIEW step 6 when code_review.codex.enabled_in_<intensity>: true"]
  - kind: agent
    ref: dev-loop:codex-review-worker
    capability: codex_code_review_wrapper
    used_by: ["REVIEW step 6 when codex backend enabled"]
  - kind: agent
    ref: dev-loop:sdd-execute-worker
    capability: execute_with_subagent_dispatch_adapter
    used_by: ["EXECUTE step 5 preferred subagent adapter"]
  - kind: skill
    ref: superpowers:test-driven-development
    capability: tdd_discipline
    used_by: ["EXECUTE step 5 when prd_disciplines declares it"]
  - kind: skill
    ref: deep-research:deep-research
    capability: deep_research
    used_by: ["IDLE step 4.5", "INVESTIGATE step 3"]
EOF

cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: agent-skills
release_branch: main
knowledge_layer: none
prd_layer: manual
prd_pipeline: full
```
EOF

OUT_DISABLED_CAPS="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$TMP" --vault "$VAULT" --project agent-skills --format json --no-write --orchestration goal 2>/dev/null)" || fail "disabled capability status failed"
echo "$OUT_DISABLED_CAPS" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.lifecycle.next_action !== "core") throw new Error("fixture must preview core");
if (j.health.state !== "healthy") throw new Error(`disabled capabilities must not degrade: ${JSON.stringify(j.health)}`);
if ((j.health.relevant_missing_optional || []).length !== 0) {
  throw new Error(`disabled capabilities classified relevant: ${JSON.stringify(j.health.relevant_missing_optional)}`);
}
process.stdout.write("ok-disabled-capabilities\n");
'

cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: agent-skills
release_branch: main
knowledge_layer: none
prd_layer: manual
prd_pipeline: full
idle_deep_research:
  enabled: true
```
EOF

IDLE_VAULT="$TMP/idle-wiki"
mkdir -p "$IDLE_VAULT"
OUT_HIGH_IDLE="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$TMP" --vault "$IDLE_VAULT" --project agent-skills --intensity high --format json --no-write --orchestration goal 2>/dev/null)" || fail "high idle capability status failed"
echo "$OUT_HIGH_IDLE" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (j.lifecycle.next_action !== "idle") throw new Error("fixture must preview idle");
if ((j.health.relevant_missing_optional || []).includes("deep-research:deep-research")) {
  throw new Error("deep research is not eligible from intensity alone");
}
process.stdout.write("ok-ineligible-deep-research\n");
'

cat > "$TMP/.claude/dev-loop.config.md" <<'EOF'
```yaml
slug: agent-skills
release_branch: main
knowledge_layer: none
prd_layer: manual
prd_pipeline: full
code_review:
  codex:
    enabled_in_normal: true
```
EOF

OUT_ENABLED_REVIEW="$(HOME="$NESTED_HOME" node "$STATUS_JS" --repo "$TMP" --vault "$VAULT" --project agent-skills --format json --no-write --orchestration goal 2>/dev/null)" || fail "enabled review status failed"
echo "$OUT_ENABLED_REVIEW" | node -e '
const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
const relevant = j.health.relevant_missing_optional || [];
for (const ref of ["codex:codex-rescue", "dev-loop:codex-review-worker"]) {
  if (!relevant.includes(ref)) throw new Error(`enabled Codex backend missing relevance: ${ref}`);
}
if (relevant.includes("dev-loop:sdd-execute-worker") || relevant.includes("superpowers:test-driven-development")) {
  throw new Error(`non-Superpowers capabilities must remain irrelevant: ${JSON.stringify(relevant)}`);
}
if (j.health.state !== "degraded") throw new Error("enabled missing review backend must degrade");
process.stdout.write("ok-enabled-review-capability\n");
'

cat > "$TMP/.claude/dev-loop.config.md" <<EOF
\`\`\`yaml
slug: agent-skills
release_branch: main
knowledge_layer: skillwiki
vault: $VAULT
ci_configured: true
merge_policy:
  strategy: pull-request
  auto_merge: true
  merge_method: squash
  require_work_item_approval: true
\`\`\`
EOF

OUT2="$(node "$STATUS_JS" --repo "$TMP" --vault "$VAULT" --project agent-skills --format json --no-write --orchestration goal 2>/dev/null)" || fail "vault status failed"

echo "$OUT2" | node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(0, "utf8"));
const skips = j.work_preview.readiness_skips || [];
if (!skips.some((s) => s.id.includes("skip"))) throw new Error("expected readiness skip");
const ready = j.work_preview.claimable_unattended || [];
if (!ready.some((id) => id.includes("ready"))) throw new Error("expected unattended ready");
const merge = j.pipeline_preview.merge;
if (merge.auto_merge_configured !== true) throw new Error("expected explicit auto-merge config");
if (merge.work_item_approved !== true) throw new Error("expected selected work-item approval");
if (merge.route_blocked !== true) throw new Error("pull-request policy on release branch must block route");
if (merge.would_create_pr !== false || merge.would_push_direct !== false) throw new Error("blocked route must not claim PR or push");
if (merge.auto_merge_eligible !== false) throw new Error("unknown CI health must fail closed");
if (!(merge.failed_gates || []).includes("ci_health:healthy")) throw new Error("expected exact healthy CI gate");
process.stdout.write("ok-readiness\n");
'

BEFORE="$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -v 'dev-loop/status' || true)"
node "$STATUS_JS" --repo "$ROOT" --project agent-skills --format json --no-write >/dev/null 2>&1 || true
AFTER="$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -v 'dev-loop/status' || true)"
if [[ "$BEFORE" != "$AFTER" ]]; then
  fail "status run mutated tracked git state"
fi

HUD_JS="$ROOT/skills/dev-loop/scripts/dev-loop-status-hud.js"
[[ -f "$HUD_JS" ]] || fail "missing dev-loop-status-hud.js"

OUT_HUD="$(node "$HUD_JS" --repo "$TMP" --project test-none --probe --format json 2>/dev/null)" || fail "hud probe failed"
echo "$OUT_HUD" | node -e '
const j = JSON.parse(require("fs").readFileSync(0,"utf8"));
if (j.schema_version !== "dev-loop-status-hud.v1") throw new Error("hud schema");
if (j.read_only !== true) throw new Error("hud read_only");
process.stdout.write("ok-hud\n");
'

printf 'test-dev-loop-status: all checks passed\n'
