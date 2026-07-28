#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_ROOT="$ROOT/skills/design-guide-usage"
CLI="$SKILL_ROOT/scripts/design-guide-usage.js"
WORK_REL="projects/agent-skills/work/2026-07-28-design-guide-usage-tracking"

fail() {
  printf 'test-design-guide-usage: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" == *"$needle"* ]] ||
    fail "$label: expected '$needle', got: $haystack"
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  [[ "$haystack" != *"$needle"* ]] ||
    fail "$label: did not expect '$needle', got: $haystack"
}

assert_command_fails() {
  local label="$1" needle="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$label: expected command to fail"
  assert_contains "$label" "$output" "$needle"
}

assert_json() {
  local label="$1" json="$2" expression="$3"
  node -e '
    const value = JSON.parse(process.argv[1]);
    const expression = process.argv[2];
    if (!Function("value", `return (${expression})`)(value)) {
      process.stderr.write(`assertion failed: ${expression}\n${JSON.stringify(value, null, 2)}\n`);
      process.exit(1);
    }
  ' "$json" "$expression" || fail "$label"
}

sha256_file() {
  node -e '
    const crypto = require("node:crypto");
    const fs = require("node:fs");
    process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"));
  ' "$1"
}

write_log() {
  local vault="$1"
  mkdir -p "$vault/$WORK_REL"
  printf '# `design-guide` Usage Log\n\n## 2026-07-28 — baseline established\n\n- Follow-up: record the first real frontend task\n' > "$vault/$WORK_REL/log.md"
}

write_input() {
  local file="$1" date="$2" project_class="$3" task_type="$4"
  local trigger_reviewed="$5" structure_compared="$6" accepted_revision="${7:-false}"
  local revision_validation="${8:-}"
  node - "$file" "$date" "$project_class" "$task_type" "$trigger_reviewed" "$structure_compared" "$accepted_revision" "$revision_validation" <<'NODE'
const fs = require("node:fs");
const [file, date, projectClass, taskType, triggerReviewed, structureCompared, acceptedRevision, revisionValidation] = process.argv.slice(2);
fs.writeFileSync(file, `${JSON.stringify({
  date,
  host: "macos-dev",
  project_class: projectClass,
  task_type: taskType,
  trigger: "explicit",
  sections_used: ["Design Tokens", "Component Hierarchy"],
  helpful_result: `Applied semantic tokens and reusable component boundaries for ${taskType}.`,
  friction: "The fixed upstream paths required deliberate translation to the target repository.",
  repeated: false,
  proposed_change: "no change",
  verification: `Focused tests and browser smoke passed for ${projectClass}.`,
  follow_up: "Record the next meaningful frontend use.",
  trigger_context_cost_reviewed: triggerReviewed === "true",
  component_structure_compared: structureCompared === "true",
  accepted_revision: acceptedRevision === "true",
  revision_validation: revisionValidation,
}, null, 2)}\n`);
NODE
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$SKILL_ROOT/SKILL.md" ]] || fail "missing companion SKILL.md"
[[ -f "$SKILL_ROOT/agents/openai.yaml" ]] || fail "missing companion agents/openai.yaml"
[[ -x "$CLI" ]] || fail "missing executable bundled recorder"
[[ ! -e "$ROOT/scripts/design-guide-usage.js" ]] || fail "recorder must not remain repository-root-only"
[[ ! -e "$SKILL_ROOT/INSTALLATION_GUIDE.md" ]] || fail "skill must not contain INSTALLATION_GUIDE.md"
[[ ! -e "$SKILL_ROOT/README.md" ]] || fail "skill must not contain README.md"
[[ ! -e "$SKILL_ROOT/scripts/install.sh" ]] || fail "skill must not install a global command"
[[ ! -e "$SKILL_ROOT/.codex-plugin/plugin.json" ]] || fail "personal skill must not contain a Codex plugin manifest"
[[ ! -e "$SKILL_ROOT/.claude-plugin/plugin.json" ]] || fail "personal skill must not contain a Claude plugin manifest"

SKILL_BODY="$(cat "$SKILL_ROOT/SKILL.md")"
assert_contains "skill trigger status" "$SKILL_BODY" 'design-guide usage status'
assert_contains "skill relative script" "$SKILL_BODY" 'scripts/design-guide-usage.js'
assert_contains "skill explicit write authority" "$SKILL_BODY" 'explicitly authorizes'
assert_not_contains "skill avoids source checkout" "$SKILL_BODY" '/Users/karlchow/Desktop/code/agent-skills'
assert_not_contains "skill avoids global PATH" "$SKILL_BODY" '~/.local/bin'

VAULT="$TMP/vault"
write_log "$VAULT"

INSTALLED_ROOT="$TMP/installed/design-guide-usage"
mkdir -p "$TMP/installed"
cp -R "$SKILL_ROOT" "$INSTALLED_ROOT"
OUTSIDE_CWD="$TMP/outside"
mkdir -p "$OUTSIDE_CWD"
INSTALLED_STATUS="$(cd "$OUTSIDE_CWD" && node "$INSTALLED_ROOT/scripts/design-guide-usage.js" status --vault "$VAULT" --json)" ||
  fail "installed-skill status should succeed outside the repository"
assert_json "installed-skill status" "$INSTALLED_STATUS" 'value.counts.uses === 0 && value.next_action === "record_first_meaningful_use"'

EMPTY_STATUS="$(node "$CLI" status --vault "$VAULT" --json)" ||
  fail "empty status should succeed"
assert_json "empty status contract" "$EMPTY_STATUS" 'value.schema === "design-guide-usage-status/v1" && value.counts.uses === 0 && value.eligible === false && value.next_action === "record_first_meaningful_use"'
EMPTY_HASH="$(sha256_file "$VAULT/$WORK_REL/log.md")"
node "$CLI" status --vault "$VAULT" >/dev/null || fail "human status should succeed"
[[ "$(sha256_file "$VAULT/$WORK_REL/log.md")" == "$EMPTY_HASH" ]] ||
  fail "status modified the log"

INPUT_1="$TMP/use-1.json"
write_input "$INPUT_1" "2026-07-28" "React dashboard" "new component" true false
BEFORE_DRY="$(sha256_file "$VAULT/$WORK_REL/log.md")"
DRY_OUT="$(node "$CLI" record --input "$INPUT_1" --vault "$VAULT" --dry-run)" ||
  fail "dry-run should succeed"
assert_contains "dry-run label" "$DRY_OUT" "dry_run: true"
assert_contains "dry-run target" "$DRY_OUT" "$WORK_REL/log.md"
assert_contains "dry-run preview" "$DRY_OUT" "entry_preview:"
assert_contains "dry-run human entry" "$DRY_OUT" "### 2026-07-28 — new component"
[[ "$(sha256_file "$VAULT/$WORK_REL/log.md")" == "$BEFORE_DRY" ]] ||
  fail "dry-run modified the log"

RECORD_OUT="$(node "$CLI" record --input "$INPUT_1" --vault "$VAULT")" ||
  fail "record should succeed"
assert_contains "record summary" "$RECORD_OUT" "recorded: true"
LOG_BODY="$(cat "$VAULT/$WORK_REL/log.md")"
assert_contains "human entry" "$LOG_BODY" "### 2026-07-28 — new component"
assert_contains "machine marker" "$LOG_BODY" "<!-- design-guide-usage/v1 "

AFTER_FIRST="$(sha256_file "$VAULT/$WORK_REL/log.md")"
assert_command_fails "duplicate evidence" "duplicate evidence id" \
  node "$CLI" record --input "$INPUT_1" --vault "$VAULT"
[[ "$(sha256_file "$VAULT/$WORK_REL/log.md")" == "$AFTER_FIRST" ]] ||
  fail "duplicate failure modified the log"

INPUT_2="$TMP/use-2.json"
write_input "$INPUT_2" "2026-07-29" "React dashboard" "page layout" false true
cat "$INPUT_2" | node "$CLI" record --input - --vault "$VAULT" >/dev/null ||
  fail "stdin record should succeed"

SECRET_INPUT="$TMP/secret.json"
write_input "$SECRET_INPUT" "2026-07-30" "React dashboard" "styling revision" false false
node - "$SECRET_INPUT" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const value = JSON.parse(fs.readFileSync(file, "utf8"));
value.friction = "Authorization: Bearer sk-live-1234567890abcdefghijklmnop";
fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
NODE
assert_command_fails "secret rejection" "likely secret" \
  node "$CLI" record --input "$SECRET_INPUT" --vault "$VAULT"

INVALID_INPUT="$TMP/invalid.json"
write_input "$INVALID_INPUT" "2026-07-30" "React dashboard" "styling revision" false false
node - "$INVALID_INPUT" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const value = JSON.parse(fs.readFileSync(file, "utf8"));
value.trigger = "sometimes";
fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
NODE
assert_command_fails "invalid enum" "trigger must be one of" \
  node "$CLI" record --input "$INVALID_INPUT" --vault "$VAULT"

MISSING_INPUT="$TMP/missing-field.json"
write_input "$MISSING_INPUT" "2026-07-30" "React dashboard" "styling revision" false false
node - "$MISSING_INPUT" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const value = JSON.parse(fs.readFileSync(file, "utf8"));
delete value.helpful_result;
fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
NODE
assert_command_fails "missing field reason" "helpful_result must be a string" \
  node "$CLI" record --input "$MISSING_INPUT" --vault "$VAULT"

MALFORMED_INPUT="$TMP/malformed-input.json"
printf '{not-json}\n' > "$MALFORMED_INPUT"
assert_command_fails "malformed JSON reason" "cannot parse input JSON" \
  node "$CLI" record --input "$MALFORMED_INPUT" --vault "$VAULT"

OVERSIZED_INPUT="$TMP/oversized-input.json"
dd if=/dev/zero of="$OVERSIZED_INPUT" bs=1024 count=65 status=none
assert_command_fails "oversized input reason" "input exceeds 65536 bytes" \
  node "$CLI" record --input "$OVERSIZED_INPUT" --vault "$VAULT"

LOCK_PATH="$VAULT/$WORK_REL/log.md.lock"
printf 'held\n' > "$LOCK_PATH"
BEFORE_LOCK="$(sha256_file "$VAULT/$WORK_REL/log.md")"
INPUT_3="$TMP/use-3.json"
write_input "$INPUT_3" "2026-07-30" "Admin console" "styling revision" false false
assert_command_fails "lock reason" "lock is already held" \
  node "$CLI" record --input "$INPUT_3" --vault "$VAULT"
rm "$LOCK_PATH"
[[ "$(sha256_file "$VAULT/$WORK_REL/log.md")" == "$BEFORE_LOCK" ]] ||
  fail "lock failure modified the log"

BEFORE_FAIL="$(sha256_file "$VAULT/$WORK_REL/log.md")"
assert_command_fails "atomic failure reason" "simulated failure before rename" \
  env DESIGN_GUIDE_USAGE_TESTING=1 DESIGN_GUIDE_USAGE_TEST_FAIL_STAGE=before-rename \
  node "$CLI" record --input "$INPUT_3" --vault "$VAULT"
[[ "$(sha256_file "$VAULT/$WORK_REL/log.md")" == "$BEFORE_FAIL" ]] ||
  fail "simulated atomic failure modified the log"

assert_command_fails "changed target reason" "evidence log changed after validation" \
  env DESIGN_GUIDE_USAGE_TESTING=1 DESIGN_GUIDE_USAGE_TEST_FAIL_STAGE=mutate-target \
  node "$CLI" record --input "$INPUT_3" --vault "$VAULT"
CHANGED_BODY="$(cat "$VAULT/$WORK_REL/log.md")"
assert_contains "external change preserved" "$CHANGED_BODY" "external concurrent change"
if [[ "$CHANGED_BODY" == *"### 2026-07-30 — styling revision"* ]]; then
  fail "changed-target failure wrote recorder input unexpectedly"
fi

node "$CLI" record --input "$INPUT_3" --vault "$VAULT" >/dev/null
INPUT_4="$TMP/use-4.json"
INPUT_5="$TMP/use-5.json"
write_input "$INPUT_4" "2026-07-31" "Admin console" "component-index review" false false true "Agent Skills validation and link checks passed."
write_input "$INPUT_5" "2026-08-01" "Marketing site" "new component" false false
node "$CLI" record --input "$INPUT_4" --vault "$VAULT" >/dev/null
node "$CLI" record --input "$INPUT_5" --vault "$VAULT" >/dev/null

READY_STATUS="$(node "$CLI" status --vault "$VAULT" --json)" ||
  fail "ready status should succeed"
assert_json "ready thresholds" "$READY_STATUS" 'value.counts.uses === 5 && value.counts.project_classes === 3 && value.counts.task_types === 4 && value.signals.trigger_context_cost_reviewed === true && value.signals.component_structure_compared === true && value.signals.unvalidated_accepted_revisions === 0 && value.eligible === true && value.next_action === "begin_human_promotion_review"'

REVISION_GAP_INPUT="$TMP/revision-gap.json"
write_input "$REVISION_GAP_INPUT" "2026-08-02" "Marketing site" "styling revision" false false true ""
assert_command_fails "revision validation requirement" "revision_validation must describe verification" \
  node "$CLI" record --input "$REVISION_GAP_INPUT" --vault "$VAULT"

SIGNAL_VAULT="$TMP/signal-vault"
write_log "$SIGNAL_VAULT"
for index in 1 2 3 4 5; do
  SIGNAL_INPUT="$TMP/signal-$index.json"
  write_input "$SIGNAL_INPUT" "2026-08-0$index" "React dashboard" "new component" false false
  node "$CLI" record --input "$SIGNAL_INPUT" --vault "$SIGNAL_VAULT" >/dev/null
done
MISSING_PROJECT_STATUS="$(node "$CLI" status --vault "$SIGNAL_VAULT" --json)"
assert_json "project-class threshold below" "$MISSING_PROJECT_STATUS" 'value.counts.uses === 5 && value.counts.project_classes === 1 && value.eligible === false && value.next_action === "record_second_project_class"'

SECOND_PROJECT_INPUT="$TMP/signal-second-project.json"
write_input "$SECOND_PROJECT_INPUT" "2026-08-06" "Admin console" "new component" false false
node "$CLI" record --input "$SECOND_PROJECT_INPUT" --vault "$SIGNAL_VAULT" >/dev/null
MISSING_TASK_STATUS="$(node "$CLI" status --vault "$SIGNAL_VAULT" --json)"
assert_json "task-type threshold below" "$MISSING_TASK_STATUS" 'value.counts.project_classes === 2 && value.counts.task_types === 1 && value.eligible === false && value.next_action === "record_second_task_type"'

SECOND_TASK_INPUT="$TMP/signal-second-task.json"
write_input "$SECOND_TASK_INPUT" "2026-08-07" "Admin console" "page layout" false false
node "$CLI" record --input "$SECOND_TASK_INPUT" --vault "$SIGNAL_VAULT" >/dev/null
MISSING_TRIGGER_STATUS="$(node "$CLI" status --vault "$SIGNAL_VAULT" --json)"
assert_json "trigger threshold below" "$MISSING_TRIGGER_STATUS" 'value.counts.task_types === 2 && value.signals.trigger_context_cost_reviewed === false && value.eligible === false && value.next_action === "review_trigger_and_context_cost"'

TRIGGER_INPUT="$TMP/signal-trigger.json"
write_input "$TRIGGER_INPUT" "2026-08-08" "Admin console" "page layout" true false
node "$CLI" record --input "$TRIGGER_INPUT" --vault "$SIGNAL_VAULT" >/dev/null
MISSING_STRUCTURE_STATUS="$(node "$CLI" status --vault "$SIGNAL_VAULT" --json)"
assert_json "structure threshold below" "$MISSING_STRUCTURE_STATUS" 'value.signals.trigger_context_cost_reviewed === true && value.signals.component_structure_compared === false && value.eligible === false && value.next_action === "compare_component_structure"'

STRUCTURE_INPUT="$TMP/signal-structure.json"
write_input "$STRUCTURE_INPUT" "2026-08-09" "Admin console" "page layout" false true
node "$CLI" record --input "$STRUCTURE_INPUT" --vault "$SIGNAL_VAULT" >/dev/null
SIGNAL_READY_STATUS="$(node "$CLI" status --vault "$SIGNAL_VAULT" --json)"
assert_json "signal thresholds at" "$SIGNAL_READY_STATUS" 'value.signals.trigger_context_cost_reviewed === true && value.signals.component_structure_compared === true && value.eligible === true'

REVISION_STATUS_VAULT="$TMP/revision-status-vault"
cp -R "$SIGNAL_VAULT" "$REVISION_STATUS_VAULT"
printf '%s\n' '<!-- design-guide-usage/v1 {"schema":"design-guide-usage/v1","id":"manual-validated-revision","date":"2026-08-10","host":"macos-dev","project_class":"Admin console","task_type":"page layout","trigger":"explicit","trigger_context_cost_reviewed":false,"component_structure_compared":false,"accepted_revision":true,"revision_validation":"Focused validation passed."} -->' >> "$REVISION_STATUS_VAULT/$WORK_REL/log.md"
REVISION_STATUS="$(node "$CLI" status --vault "$REVISION_STATUS_VAULT" --json)"
assert_json "validated revision remains eligible" "$REVISION_STATUS" 'value.signals.unvalidated_accepted_revisions === 0 && value.eligible === true && value.next_action === "begin_human_promotion_review"'

MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/skillwiki" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "path" ]; then
  printf '%s\n' '{"ok":true,"data":{"path":"$VAULT"}}'
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/skillwiki"
RESOLVED_STATUS="$(cd "$OUTSIDE_CWD" && PATH="$MOCK_BIN:$PATH" node "$INSTALLED_ROOT/scripts/design-guide-usage.js" status --json)" ||
  fail "skillwiki path resolution should succeed"
assert_json "resolved vault status" "$RESOLVED_STATUS" 'value.eligible === true && value.target.endsWith("projects/agent-skills/work/2026-07-28-design-guide-usage-tracking/log.md")'

MALFORMED_VAULT="$TMP/malformed-vault"
write_log "$MALFORMED_VAULT"
printf '\n<!-- design-guide-usage/v1 {not-json} -->\n' >> "$MALFORMED_VAULT/$WORK_REL/log.md"
assert_command_fails "malformed marker reason" "malformed evidence marker" \
  node "$CLI" status --vault "$MALFORMED_VAULT" --json

INVALID_MARKER_VAULT="$TMP/invalid-marker-vault"
write_log "$INVALID_MARKER_VAULT"
printf '%s\n' '<!-- design-guide-usage/v1 {"schema":"design-guide-usage/v1","id":"invalid-marker","date":"2026-08-10","host":"macos-dev","project_class":"Admin console","task_type":"page layout","trigger":"explicit","trigger_context_cost_reviewed":"yes","component_structure_compared":false,"accepted_revision":false,"revision_validation":""} -->' >> "$INVALID_MARKER_VAULT/$WORK_REL/log.md"
assert_command_fails "invalid marker shape reason" "trigger_context_cost_reviewed must be a boolean" \
  node "$CLI" status --vault "$INVALID_MARKER_VAULT" --json

printf 'test-design-guide-usage: all checks passed\n'
