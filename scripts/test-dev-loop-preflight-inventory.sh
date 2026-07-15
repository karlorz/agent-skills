#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/skills/dev-loop/scripts/preflight-inventory.js"

fail() {
  printf 'test-dev-loop-preflight-inventory: %s\n' "$1" >&2
  exit 1
}

write_work_spec() {
  local dir="$1" status="$2" priority="$3" title="$4"
  local project="${5:-agent-skills}"
  mkdir -p "$dir"
  cat > "$dir/spec.md" <<EOF
---
title: "$title"
name: "$(basename "$dir")"
description: "$title"
kind: feature
status: $status
priority: $priority
project: "[[$project]]"
created: 2026-06-05
updated: 2026-06-05
started: 2026-06-05
---

# $title
EOF
}

write_plan() {
  local dir="$1"
  cat > "$dir/plan.md" <<EOF
---
title: "Plan: $(basename "$dir")"
name: "$(basename "$dir")-plan"
description: "Plan"
kind: feature
status: planned
priority: medium
project: "[[agent-skills]]"
created: 2026-06-05
updated: 2026-06-05
started: 2026-06-05
---

# Plan
EOF
}

write_capture() {
  local file="$1" kind="$2" project="$3"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
---
source_url:
ingested: 2026-06-05
kind: $kind
project: "$project"
---

Capture body.
EOF
}

write_capture_body() {
  local file="$1" kind="$2" project="$3" body="$4"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
---
source_url:
ingested: 2026-06-05
kind: $kind
project: "$project"
---

$body
EOF
}

init_git_repo() {
  local repo="$1" remote="${2:-}"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "dev-loop-test@example.invalid"
  git -C "$repo" config user.name "Dev Loop Test"
  printf '# fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "chore: initialize fixture repo"
  if [ -n "$remote" ]; then
    git -C "$repo" remote add origin "$remote"
  fi
}

run_inventory() {
  node "$HELPER" --project agent-skills --vault "$VAULT" --repo "$REPO" "$@"
}

assert_json() {
  local json="$1" script="$2"
  node - "$json" "$script" <<'NODE'
const data = JSON.parse(process.argv[2]);
const script = process.argv[3];
const assert = (condition, message) => {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
};
Function("data", "assert", script)(data, assert);
NODE
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VAULT="$TMP_DIR/wiki"
REPO="$TMP_DIR/repo"
WORK="$VAULT/projects/agent-skills/work"
OTHER_WORK="$VAULT/projects/other-project/work"
mkdir -p "$WORK" "$OTHER_WORK" "$VAULT/raw/transcripts" "$VAULT/projects/agent-skills/history" "$REPO"

git -C "$REPO" init -q
git -C "$REPO" config user.email "dev-loop-test@example.invalid"
git -C "$REPO" config user.name "Dev Loop Test"

mkdir -p "$REPO/scripts" "$REPO/skills/dev-loop"
cat > "$REPO/scripts/test-widget-review.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Contract fixture for implemented-capture detection.
required_worker="widget-reviewer"
required_skill="widget:review"
printf '%s %s\n' "$required_worker" "$required_skill"
EOF
cat > "$REPO/skills/dev-loop/dependencies.yaml" <<'EOF'
required:
  - ref: widget-reviewer
    fallback: inline widget:review
EOF
cat > "$REPO/scripts/test-critical-path-audit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Generic workflow vocabulary should not count as a focused implementation.
printf '%s\n' 'critical_paths.*.code'
printf '%s\n' 'git status --short'
printf '%s\n' 'git diff --name-only'
printf '%s\n' 'critical-path dirty-tree audit'
EOF
cat > "$REPO/scripts/test-implemented-evidence-audit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Classifier vocabulary should not prove that a classifier bug is already fixed.
printf '%s\n' 'possibly_implemented_without_closure'
printf '%s\n' 'body-derived implementation terms'
printf '%s\n' 'implemented-evidence heuristic'
printf '%s\n' 'implemented-capture detection'
printf '%s\n' 'dirty-critical-path'
printf '%s\n' 'all-projects vault-only inventory'
printf '%s\n' 'simplify-worker remains a positive control'
EOF
mkdir -p "$REPO/archive" "$REPO/logs"
cat > "$REPO/archive/dev-loop-research.md" <<'EOF'
This archived note references a work-item queue and says the helper must not
auto-create planned work from generic critical_paths vocabulary.
EOF
cat > "$REPO/logs/dev-loop-stale.txt" <<'EOF'
critical_paths work-item auto-create
EOF
git -C "$REPO" add scripts skills archive logs
git -C "$REPO" commit -q -m "fix(dev-loop): implement widget-reviewer widget:review gate"

write_work_spec "$WORK/2026-06-05-planned-high" planned high "Planned High"
write_plan "$WORK/2026-06-05-planned-high"
write_work_spec "$WORK/2026-06-05-in-progress" in-progress medium "In Progress"
write_plan "$WORK/2026-06-05-in-progress"
write_work_spec "$WORK/2026-06-05-ready-high" ready high "Ready High"
write_plan "$WORK/2026-06-05-ready-high"
write_work_spec "$WORK/2026-06-05-active-high" active high "Active High"
write_plan "$WORK/2026-06-05-active-high"
write_work_spec "$WORK/2026-06-05-proposed-legacy" proposed medium "Proposed Legacy"
write_plan "$WORK/2026-06-05-proposed-legacy"
write_work_spec "$WORK/2026-06-05-completed" completed medium "Completed"
write_plan "$WORK/2026-06-05-completed"
write_work_spec "$WORK/2026-06-05-done-alias" done medium "Done Alias"
write_plan "$WORK/2026-06-05-done-alias"
write_work_spec "$WORK/2026-06-05-spec-only" planned medium "Spec Only"
write_work_spec "$OTHER_WORK/2026-06-05-other-planned-high" planned high "Other Planned High" other-project
write_plan "$OTHER_WORK/2026-06-05-other-planned-high"
mkdir -p "$WORK/_archive/2026-06-05-archived-container"
write_work_spec "$VAULT/projects/agent-skills/history/2026-06-05-history-item" planned high "History Item"

write_capture "$VAULT/raw/transcripts/2026-06-05-task-agent-skills.md" task "[[agent-skills]]"
write_capture "$VAULT/raw/transcripts/2026-06-05-bug-agent-skills.md" bug "[[agent-skills]]"
write_capture "$VAULT/raw/transcripts/2026-06-05-idea-agent-skills.md" idea "[[agent-skills]]"
write_capture "$VAULT/raw/transcripts/2026-06-05-task-other.md" task "[[other-project]]"
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-widget-reviewer-implemented.md" bug "[[agent-skills]]" $'# bug: widget reviewer gate still surfaces\n\nThe dev-loop review path should require `widget-reviewer` and `widget:review` before merge. The repo implementation already added the contract test, so this raw capture should become closure hygiene instead of normal capture work.'
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-other-widget-reviewer.md" bug "[[other-project]]" $'# bug: other project widget reviewer\n\nThe other project mentions `widget-reviewer` and `widget:review`, but all-project discovery must not use the current repo to decide this capture was implemented.'
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-filename-only-widget-reviewer.md" bug "[[agent-skills]]" $'# bug: generic stale report\n\nThis capture body intentionally has no implementation identifiers. A matching filename alone must not downgrade it to hygiene.'
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-single-token-widget.md" bug "[[agent-skills]]" $'# bug: widget\n\nFix widget.'
write_capture_body "$VAULT/raw/transcripts/2026-06-05-task-dirty-critical-path-detector.md" task "[[agent-skills]]" $'# task: dirty critical-path detector\n\nPreflight should intersect `critical_paths.*.code`, `git status --short`, `git diff --name-only`, and `critical-path` dirty-tree evidence without treating broad `critical_paths`, `work-item`, or `auto-create` vocabulary as proof that the detector already exists.'
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-implemented-evidence-false-positive.md" bug "[[agent-skills]]" $'# bug: implemented-evidence false positive\n\nThe `possibly_implemented_without_closure` helper should not treat classifier vocabulary like `body-derived`, `implemented-capture`, `task/bug`, `dirty-critical-path`, `all-projects`, `vault-only`, or `/Users/karlchow/Desktop/code/agent-skills` as proof that this bug is fixed. Keep the existing simplify-worker fixture in hygiene, but this bug should stay in captures until focused classifier behavior lands.'

implemented_capture="$VAULT/raw/transcripts/2026-06-05-bug-widget-reviewer-implemented.md"
implemented_capture_hash_before="$(shasum -a 256 "$implemented_capture" | awk '{print $1}')"

all_json="$(run_inventory --all)"
assert_json "$all_json" '
  const ids = data.candidates.map((candidate) => candidate.id);
  assert(ids.includes("2026-06-05-planned-high"), "planned work missing");
  assert(ids.includes("2026-06-05-in-progress"), "in-progress work missing");
  assert(ids.includes("2026-06-05-ready-high"), "ready work missing");
  assert(ids.includes("2026-06-05-active-high"), "active work missing");
  assert(ids.includes("2026-06-05-proposed-legacy"), "legacy proposed work missing");
  assert(data.candidates.find((candidate) => candidate.id === "2026-06-05-proposed-legacy").repairable === true, "legacy proposed should be repairable");
  assert(!ids.includes("2026-06-05-completed"), "completed work should be skipped");
  assert(!ids.includes("2026-06-05-done-alias"), "done-status work should be skipped like completed");
  assert(!ids.includes("_archive"), "archive container should be skipped");
  assert(!ids.includes("2026-06-05-history-item"), "history work should be ignored");
  assert(ids.includes("2026-06-05-task-agent-skills"), "project task capture missing");
  assert(ids.includes("2026-06-05-bug-agent-skills"), "project bug capture missing");
  assert(!ids.includes("2026-06-05-idea-agent-skills"), "idea capture should be skipped");
  assert(!ids.includes("2026-06-05-task-other"), "other project capture should be skipped");
  const implemented = data.candidates.find((candidate) => candidate.id === "2026-06-05-bug-widget-reviewer-implemented");
  assert(implemented, "implemented-but-unclosed capture should still be visible in all-lane inventory");
  assert(implemented.lane === "hygiene", "implemented-but-unclosed capture should be projected to hygiene");
  assert(implemented.findings.includes("possibly_implemented_without_closure"), "implemented capture should include hygiene finding");
  assert(implemented.implemented_evidence, "implemented capture should include auditable evidence");
  assert(implemented.implemented_evidence.terms.includes("widget-reviewer"), "implemented evidence should include body-derived worker term");
  assert(implemented.implemented_evidence.terms.includes("widget:review"), "implemented evidence should include body-derived skill term");
  assert(implemented.implemented_evidence.git_matches.some((line) => line.includes("widget-reviewer")), "implemented evidence should include matching commit");
  assert(implemented.implemented_evidence.audit_files.some((file) => file === "scripts/test-widget-review.sh"), "implemented evidence should include test audit file");
  assert(ids.includes("2026-06-05-bug-filename-only-widget-reviewer"), "filename-only weak capture should remain visible");
  assert(ids.includes("2026-06-05-bug-single-token-widget"), "single-token weak capture should remain visible");
  const dirtyCriticalPath = data.candidates.find((candidate) => candidate.id === "2026-06-05-task-dirty-critical-path-detector");
  assert(dirtyCriticalPath, "dirty critical-path detector task should remain visible");
  assert(dirtyCriticalPath.lane === "captures", "broad critical-path vocabulary alone must not reclassify the detector task to hygiene");
  assert(!dirtyCriticalPath.implemented_evidence, "broad critical-path vocabulary alone must not attach implemented evidence");
  const implementedEvidenceFalsePositive = data.candidates.find((candidate) => candidate.id === "2026-06-05-bug-implemented-evidence-false-positive");
  assert(implementedEvidenceFalsePositive, "implemented-evidence false-positive bug should remain visible");
  assert(implementedEvidenceFalsePositive.lane === "captures", "classifier/meta vocabulary alone must not reclassify the false-positive bug to hygiene");
  assert(!implementedEvidenceFalsePositive.implemented_evidence, "classifier/meta vocabulary alone must not attach implemented evidence");
'

all_projects_json="$(node "$HELPER" --all-projects --vault "$VAULT" --repo "$REPO" --all)"
assert_json "$all_projects_json" '
  assert(data.scope.all_projects === true, "all-projects scope flag missing");
  assert(data.scope.repo_evidence === false, "all-projects discovery should be vault-only");
  assert(data.repo === null, "all-projects discovery should not claim one repo");
  assert(data.repo_resolution.status === "skipped_all_projects_vault_only", "all-projects discovery should record vault-only repo resolution");
  assert(data.project === null, "all-projects output should not claim one active project");
  const projects = data.projects.map((project) => project.slug);
  assert(projects.includes("agent-skills"), "agent-skills summary missing");
  assert(projects.includes("other-project"), "other-project summary missing");
  const idsByProject = new Map(data.candidates.map((candidate) => [`${candidate.project_slug}:${candidate.id}`, candidate]));
  assert(idsByProject.has("agent-skills:2026-06-05-planned-high"), "agent-skills work missing from all-projects inventory");
  assert(idsByProject.has("other-project:2026-06-05-other-planned-high"), "other-project work missing from all-projects inventory");
  assert(idsByProject.has("other-project:2026-06-05-task-other"), "other-project capture missing from all-projects inventory");
  assert(idsByProject.has("other-project:2026-06-05-bug-other-widget-reviewer"), "other-project widget capture missing from all-projects inventory");
  assert(idsByProject.get("other-project:2026-06-05-bug-other-widget-reviewer").lane === "captures", "all-projects should not convert other-project capture to hygiene using the current repo");
  assert(!idsByProject.get("other-project:2026-06-05-bug-other-widget-reviewer").implemented_evidence, "all-projects should not attach implemented evidence from the current repo");
  assert(data.candidates.every((candidate) => candidate.git_matches.length === 0), "all-projects selected candidates should not receive current-repo git matches");
  assert(idsByProject.get("other-project:2026-06-05-other-planned-high").path === "projects/other-project/work/2026-06-05-other-planned-high/spec.md", "other-project work path should remain project-local");
  assert(data.totals.projects >= 2, "all-projects totals should include project count");
'

PROJECT_REPOS="$VAULT/projects/llm-wiki/architecture/project-repos.yaml"
mkdir -p "$(dirname "$PROJECT_REPOS")"
cat > "$PROJECT_REPOS" <<EOF
schema_version: 1
coordinator_project: llm-wiki
hosts:
  macos-dev:
    users:
      karlchow:
        workspace_roots:
          - ~/Desktop/code
  sg01:
    users:
      root:
        workspace_roots:
          - ~/projects
  sg02:
    users:
      agent-memory:
        workspace_roots:
          - ~/projects
projects:
  agent-skills:
    remote_urls:
      - git@github.com:karlorz/agent-skills.git
      - https://github.com/karlorz/agent-skills.git
  llm-wiki:
    remote_urls:
      - git@github.com:karlorz/llm-wiki.git
      - https://github.com/karlorz/llm-wiki.git
    host_overrides:
      sg02:
        users:
          agent-memory:
            repo_path: $TMP_DIR/agent-memory/llm-wiki
  missing-project:
  dupe-project:
  wrong-remote:
    remote_urls:
      - https://github.com/karlorz/wrong-remote.git
EOF

mkdir -p "$VAULT/projects/llm-wiki/work" "$VAULT/projects/missing-project/work" \
  "$VAULT/projects/dupe-project/work" "$VAULT/projects/wrong-remote/work"

MAC_HOME="$TMP_DIR/home-macos"
LINUX_HOME="$TMP_DIR/home-linux"
init_git_repo "$MAC_HOME/Desktop/code/agent-skills" "git@github.com:karlorz/agent-skills.git"
init_git_repo "$LINUX_HOME/projects/agent-skills" "https://github.com/karlorz/agent-skills.git"
init_git_repo "$TMP_DIR/agent-memory/llm-wiki" "git@github.com:karlorz/llm-wiki.git"
init_git_repo "$MAC_HOME/Desktop/code/dupe-project"
init_git_repo "$TMP_DIR/alternate-code/dupe-project"
init_git_repo "$MAC_HOME/Desktop/code/wrong-remote" "https://example.invalid/not-the-configured-repo.git"

mac_resolved_json="$(HOME="$MAC_HOME" node "$HELPER" --project agent-skills --vault "$VAULT" --project-repos "$PROJECT_REPOS" --host-id macos-dev --repo-user karlchow --all)"
assert_json "$mac_resolved_json" '
  assert(data.repo_resolution.status === "resolved", "macos-dev repo should resolve");
  assert(data.repo_resolution.path.endsWith("/home-macos/Desktop/code/agent-skills"), "macos-dev should resolve ~/Desktop/code/agent-skills");
  assert(data.scope.repo_evidence === true, "resolved project inventory should enable repo evidence");
  assert(typeof data.repo_resolution.git_context.branch === "string" && data.repo_resolution.git_context.branch.length > 0, "resolved repo should record branch context");
  assert(data.repo_resolution.git_context.dirty === false, "resolved repo should record dirty context");
  assert(data.repo_resolution.git_context.ahead === null, "resolved repo should record ahead context without requiring upstream");
  assert(data.repo_resolution.git_context.behind === null, "resolved repo should record behind context without requiring upstream");
'

linux_resolved_json="$(HOME="$LINUX_HOME" node "$HELPER" --project agent-skills --vault "$VAULT" --project-repos "$PROJECT_REPOS" --host-id sg01 --repo-user root --all)"
assert_json "$linux_resolved_json" '
  assert(data.repo_resolution.status === "resolved", "sg01 repo should resolve");
  assert(data.repo_resolution.path.endsWith("/home-linux/projects/agent-skills"), "sg01 should resolve ~/projects/agent-skills");
'

override_resolved_json="$(HOME="$LINUX_HOME" node "$HELPER" --project llm-wiki --vault "$VAULT" --project-repos "$PROJECT_REPOS" --host-id sg02 --repo-user agent-memory --all)"
assert_json "$override_resolved_json" '
  assert(data.repo_resolution.status === "resolved", "explicit host override should resolve");
  assert(data.repo_resolution.path.endsWith("/agent-memory/llm-wiki"), "sg02 should use explicit llm-wiki override");
'

missing_json="$(HOME="$MAC_HOME" node "$HELPER" --project missing-project --vault "$VAULT" --project-repos "$PROJECT_REPOS" --host-id macos-dev --repo-user karlchow --all)"
assert_json "$missing_json" '
  assert(data.repo_resolution.status === "unresolved", "missing checkout should be explicit unresolved status");
  assert(data.scope.repo_evidence === false, "missing checkout should disable repo evidence");
'

host_unknown_json="$(HOME="$MAC_HOME" node "$HELPER" --project agent-skills --vault "$VAULT" --project-repos "$PROJECT_REPOS" --host-id unknown-host --repo-user karlchow --all)"
assert_json "$host_unknown_json" '
  assert(data.repo_resolution.status === "host_unknown", "unknown host should be explicit host_unknown status");
  assert(data.scope.repo_evidence === false, "unknown host should disable repo evidence");
'

ambiguous_json="$(HOME="$MAC_HOME" node "$HELPER" --project dupe-project --vault "$VAULT" --project-repos "$PROJECT_REPOS" --host-id macos-dev --repo-user karlchow --workspace-root "$MAC_HOME/Desktop/code" --workspace-root "$TMP_DIR/alternate-code" --all)"
assert_json "$ambiguous_json" '
  assert(data.repo_resolution.status === "ambiguous", "duplicate local matches should be ambiguous");
  assert(data.repo_resolution.candidates.length === 2, "ambiguous result should list both candidate paths");
  assert(data.scope.repo_evidence === false, "ambiguous checkout should disable repo evidence");
'

wrong_remote_json="$(HOME="$MAC_HOME" node "$HELPER" --project wrong-remote --vault "$VAULT" --project-repos "$PROJECT_REPOS" --host-id macos-dev --repo-user karlchow --all)"
assert_json "$wrong_remote_json" '
  assert(data.repo_resolution.status === "wrong_remote", "remote mismatch should be explicit wrong_remote status");
  assert(data.repo_resolution.path.endsWith("/home-macos/Desktop/code/wrong-remote"), "wrong_remote should report the matching local path");
  assert(typeof data.repo_resolution.git_context.branch === "string" && data.repo_resolution.git_context.branch.length > 0, "wrong_remote should still record branch context");
  assert(data.scope.repo_evidence === false, "wrong remote should disable repo evidence");
'

limited_json="$(run_inventory --limit 2)"
assert_json "$limited_json" '
  assert(data.candidates.length === 2, "limit should restrict selected candidates");
  assert(data.totals.filtered_candidates > data.candidates.length, "filtered total should exceed selected limit");
'

limited_mixed_json="$(run_inventory --limit 5)"
assert_json "$limited_mixed_json" '
  const ids = data.candidates.map((candidate) => candidate.id);
  assert(!ids.includes("2026-06-05-bug-widget-reviewer-implemented"), "hygiene-only implemented capture should not crowd out real default candidates");
'

work_json="$(run_inventory --all --lane work)"
assert_json "$work_json" '
  assert(data.candidates.every((candidate) => candidate.lane === "work"), "lane work should exclude non-work candidates");
  assert(!data.skipped.some((item) => item.lane === "captures"), "lane work should not scan capture transcripts");
  assert(!data.candidates.some((candidate) => candidate.findings.includes("possibly_implemented_without_closure")), "lane work should not run implemented-capture evidence");
  assert(!data.candidates.some((candidate) => String(candidate.id).startsWith("dirty-critical-path-")), "lane work should not run dirty critical-path detection");
'

captures_json="$(run_inventory --all --lane captures)"
assert_json "$captures_json" '
  const ids = data.candidates.map((candidate) => candidate.id);
  assert(!ids.includes("2026-06-05-bug-widget-reviewer-implemented"), "captures lane should exclude implemented hygiene finding");
  assert(ids.includes("2026-06-05-bug-filename-only-widget-reviewer"), "filename-only weak capture should remain in captures lane");
  assert(ids.includes("2026-06-05-bug-single-token-widget"), "single-token weak capture should remain in captures lane");
  assert(ids.includes("2026-06-05-task-dirty-critical-path-detector"), "broad critical-path vocabulary should keep the detector task in captures");
  assert(ids.includes("2026-06-05-bug-implemented-evidence-false-positive"), "implemented-evidence false-positive bug should remain in captures lane");
'

hygiene_json="$(run_inventory --all --lane hygiene)"
assert_json "$hygiene_json" '
  const specOnly = data.candidates.find((candidate) => candidate.id === "2026-06-05-spec-only");
  assert(!data.candidates.some((candidate) => candidate.id === "_archive"), "hygiene lane should skip archive containers");
  assert(specOnly, "hygiene lane should include active work missing plan");
  assert(specOnly.lane === "hygiene", "hygiene projection should report hygiene lane");
  assert(specOnly.lanes.includes("work") && specOnly.lanes.includes("hygiene"), "hygiene candidate should retain source lanes");
  assert(specOnly.findings.includes("missing_plan"), "hygiene candidate should report missing_plan");
  const implemented = data.candidates.find((candidate) => candidate.id === "2026-06-05-bug-widget-reviewer-implemented");
  assert(implemented, "hygiene lane should include implemented-but-unclosed capture");
  assert(implemented.findings.includes("possibly_implemented_without_closure"), "hygiene implemented capture should include explicit finding");
'

single_json="$(run_inventory --all --work 2026-06-05-proposed-legacy)"
assert_json "$single_json" '
  assert(data.candidates.length === 1, "single work selection should return one candidate");
  assert(data.candidates[0].id === "2026-06-05-proposed-legacy", "single work selection returned wrong candidate");
'

node_dir="$(dirname "$(command -v node)")"
missing_skillwiki_json="$(PATH="$node_dir" run_inventory --all --work 2026-06-05-planned-high)"
assert_json "$missing_skillwiki_json" '
  assert(data.errors.length === 0, "missing skillwiki should not become a top-level inventory error");
  assert(data.candidates.length === 1, "missing skillwiki fixture should still return selected work");
  assert(data.candidates[0].validation.available === false, "validation should be marked unavailable");
  assert(data.candidates[0].validation.raw.includes("ENOENT"), "validation raw output should explain missing skillwiki");
'

implemented_capture_hash_after="$(shasum -a 256 "$implemented_capture" | awk '{print $1}')"
[ "$implemented_capture_hash_before" = "$implemented_capture_hash_after" ] ||
  fail "implemented-capture detection must not modify raw transcripts"

DETECTOR_VAULT="$TMP_DIR/detector-wiki"
DETECTOR_REPO="$TMP_DIR/detector-repo"
DETECTOR_WORK="$DETECTOR_VAULT/projects/agent-skills/work"
mkdir -p "$DETECTOR_WORK" "$DETECTOR_VAULT/raw/transcripts"
init_git_repo "$DETECTOR_REPO"

mkdir -p "$DETECTOR_REPO/.claude" "$DETECTOR_REPO/skills/dev-loop/scripts"
cat > "$DETECTOR_REPO/.claude/dev-loop.config.md" <<'EOF'
# Detector Fixture

## Critical Paths

```yaml
critical_paths:
  preflight_inventory:
    code:
      - skills/dev-loop/scripts/preflight-inventory.js
```
EOF
cat > "$DETECTOR_REPO/skills/dev-loop/scripts/preflight-inventory.js" <<'EOF'
module.exports = {
  detector: false,
};
EOF
git -C "$DETECTOR_REPO" add .claude skills
git -C "$DETECTOR_REPO" commit -q -m "test: seed critical path fixture"

write_work_spec "$DETECTOR_WORK/2026-06-05-preflight-inventory-follow-up" completed medium "Preflight Inventory Follow Up"
write_plan "$DETECTOR_WORK/2026-06-05-preflight-inventory-follow-up"
cat >> "$DETECTOR_WORK/2026-06-05-preflight-inventory-follow-up/spec.md" <<'EOF'

Touches `skills/dev-loop/scripts/preflight-inventory.js`.
EOF

cat > "$DETECTOR_REPO/skills/dev-loop/scripts/preflight-inventory.js" <<'EOF'
module.exports = {
  detector: true,
};
EOF

detector_json="$(node "$HELPER" --project agent-skills --vault "$DETECTOR_VAULT" --repo "$DETECTOR_REPO" --all --lane hygiene)"
assert_json "$detector_json" '
  const finding = data.candidates.find((candidate) => candidate.id === "dirty-critical-path-preflight_inventory");
  assert(finding, "dirty critical-path finding should be emitted when a matching critical path file is dirty");
  assert(finding.findings.includes("dirty_critical_path_without_active_work"), "dirty critical-path finding should include explicit hygiene code");
  assert(finding.dirty_critical_path, "dirty critical-path finding should include detail payload");
  assert(finding.dirty_critical_path.name === "preflight_inventory", "dirty critical-path finding should report the matching critical path name");
  assert(finding.dirty_critical_path.changed_files.includes("skills/dev-loop/scripts/preflight-inventory.js"), "dirty critical-path finding should report the changed file");
  assert(finding.dirty_critical_path.reopen_work_item_slugs.includes("2026-06-05-preflight-inventory-follow-up"), "dirty critical-path finding should suggest reopening related completed work");
  assert(typeof finding.dirty_critical_path.create_work_item_slug === "string" && finding.dirty_critical_path.create_work_item_slug.length > 0, "dirty critical-path finding should suggest a create slug");
'

UNRELATED_VAULT="$TMP_DIR/unrelated-wiki"
UNRELATED_REPO="$TMP_DIR/unrelated-repo"
mkdir -p "$UNRELATED_VAULT/projects/agent-skills/work" "$UNRELATED_VAULT/raw/transcripts"
init_git_repo "$UNRELATED_REPO"
mkdir -p "$UNRELATED_REPO/.claude" "$UNRELATED_REPO/skills/dev-loop/scripts"
cat > "$UNRELATED_REPO/.claude/dev-loop.config.md" <<'EOF'
# Detector Fixture

## Critical Paths

```yaml
critical_paths:
  preflight_inventory:
    code:
      - skills/dev-loop/scripts/preflight-inventory.js
```
EOF
cat > "$UNRELATED_REPO/skills/dev-loop/scripts/preflight-inventory.js" <<'EOF'
module.exports = {
  detector: false,
};
EOF
git -C "$UNRELATED_REPO" add .claude skills
git -C "$UNRELATED_REPO" commit -q -m "test: seed unrelated critical path fixture"
printf 'dirty unrelated file\n' >> "$UNRELATED_REPO/README.md"

unrelated_json="$(node "$HELPER" --project agent-skills --vault "$UNRELATED_VAULT" --repo "$UNRELATED_REPO" --all --lane hygiene)"
assert_json "$unrelated_json" '
  assert(!data.candidates.some((candidate) => candidate.findings.includes("dirty_critical_path_without_active_work")), "dirty unrelated files must not emit critical-path noise");
'

NO_CRITICAL_VAULT="$TMP_DIR/no-critical-wiki"
NO_CRITICAL_REPO="$TMP_DIR/no-critical-repo"
mkdir -p "$NO_CRITICAL_VAULT/projects/agent-skills/work" "$NO_CRITICAL_VAULT/raw/transcripts"
init_git_repo "$NO_CRITICAL_REPO"
mkdir -p "$NO_CRITICAL_REPO/skills/dev-loop/scripts"
cat > "$NO_CRITICAL_REPO/skills/dev-loop/scripts/preflight-inventory.js" <<'EOF'
module.exports = {
  detector: false,
};
EOF
git -C "$NO_CRITICAL_REPO" add skills
git -C "$NO_CRITICAL_REPO" commit -q -m "test: seed no critical path fixture"
printf 'dirty critical path without config\n' >> "$NO_CRITICAL_REPO/skills/dev-loop/scripts/preflight-inventory.js"

no_critical_json="$(node "$HELPER" --project agent-skills --vault "$NO_CRITICAL_VAULT" --repo "$NO_CRITICAL_REPO" --all --lane hygiene)"
assert_json "$no_critical_json" '
  assert(!data.candidates.some((candidate) => candidate.findings.includes("dirty_critical_path_without_active_work")), "repos without critical_paths should keep existing inventory output");
'

printf 'test-dev-loop-preflight-inventory: ok\n'
