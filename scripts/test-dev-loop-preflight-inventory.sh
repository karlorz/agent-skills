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
  mkdir -p "$dir"
  cat > "$dir/spec.md" <<EOF
---
title: "$title"
name: "$(basename "$dir")"
description: "$title"
kind: feature
status: $status
priority: $priority
project: "[[agent-skills]]"
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
mkdir -p "$WORK" "$VAULT/raw/transcripts" "$VAULT/projects/agent-skills/history" "$REPO"

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
git -C "$REPO" add scripts skills
git -C "$REPO" commit -q -m "fix(dev-loop): implement widget-reviewer widget:review gate"

write_work_spec "$WORK/2026-06-05-planned-high" planned high "Planned High"
write_plan "$WORK/2026-06-05-planned-high"
write_work_spec "$WORK/2026-06-05-in-progress" in-progress medium "In Progress"
write_plan "$WORK/2026-06-05-in-progress"
write_work_spec "$WORK/2026-06-05-proposed-legacy" proposed medium "Proposed Legacy"
write_plan "$WORK/2026-06-05-proposed-legacy"
write_work_spec "$WORK/2026-06-05-completed" completed medium "Completed"
write_plan "$WORK/2026-06-05-completed"
write_work_spec "$WORK/2026-06-05-spec-only" planned medium "Spec Only"
write_work_spec "$VAULT/projects/agent-skills/history/2026-06-05-history-item" planned high "History Item"

write_capture "$VAULT/raw/transcripts/2026-06-05-task-agent-skills.md" task "[[agent-skills]]"
write_capture "$VAULT/raw/transcripts/2026-06-05-bug-agent-skills.md" bug "[[agent-skills]]"
write_capture "$VAULT/raw/transcripts/2026-06-05-idea-agent-skills.md" idea "[[agent-skills]]"
write_capture "$VAULT/raw/transcripts/2026-06-05-task-other.md" task "[[other-project]]"
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-widget-reviewer-implemented.md" bug "[[agent-skills]]" $'# bug: widget reviewer gate still surfaces\n\nThe dev-loop review path should require `widget-reviewer` and `widget:review` before merge. The repo implementation already added the contract test, so this raw capture should become closure hygiene instead of normal capture work.'
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-filename-only-widget-reviewer.md" bug "[[agent-skills]]" $'# bug: generic stale report\n\nThis capture body intentionally has no implementation identifiers. A matching filename alone must not downgrade it to hygiene.'
write_capture_body "$VAULT/raw/transcripts/2026-06-05-bug-single-token-widget.md" bug "[[agent-skills]]" $'# bug: widget\n\nFix widget.'

implemented_capture="$VAULT/raw/transcripts/2026-06-05-bug-widget-reviewer-implemented.md"
implemented_capture_hash_before="$(shasum -a 256 "$implemented_capture" | awk '{print $1}')"

all_json="$(run_inventory --all)"
assert_json "$all_json" '
  const ids = data.candidates.map((candidate) => candidate.id);
  assert(ids.includes("2026-06-05-planned-high"), "planned work missing");
  assert(ids.includes("2026-06-05-in-progress"), "in-progress work missing");
  assert(ids.includes("2026-06-05-proposed-legacy"), "legacy proposed work missing");
  assert(data.candidates.find((candidate) => candidate.id === "2026-06-05-proposed-legacy").repairable === true, "legacy proposed should be repairable");
  assert(!ids.includes("2026-06-05-completed"), "completed work should be skipped");
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
'

captures_json="$(run_inventory --all --lane captures)"
assert_json "$captures_json" '
  const ids = data.candidates.map((candidate) => candidate.id);
  assert(!ids.includes("2026-06-05-bug-widget-reviewer-implemented"), "captures lane should exclude implemented hygiene finding");
  assert(ids.includes("2026-06-05-bug-filename-only-widget-reviewer"), "filename-only weak capture should remain in captures lane");
  assert(ids.includes("2026-06-05-bug-single-token-widget"), "single-token weak capture should remain in captures lane");
'

hygiene_json="$(run_inventory --all --lane hygiene)"
assert_json "$hygiene_json" '
  const specOnly = data.candidates.find((candidate) => candidate.id === "2026-06-05-spec-only");
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

printf 'test-dev-loop-preflight-inventory: ok\n'
