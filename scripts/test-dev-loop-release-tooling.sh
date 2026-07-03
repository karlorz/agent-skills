#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'test-dev-loop-release-tooling: %s\n' "$1" >&2
  exit 1
}

# This test verifies the awk-written versions by reading them back with jq (an
# independent implementation, so a shared bug can't hide). bump-version.sh
# itself stays jq-free; the dependency is the test's alone, so fail clearly if
# jq is absent rather than letting a downstream jq invocation error out.
command -v jq >/dev/null 2>&1 || fail "jq is required to run this test; install it (e.g. 'brew install jq')"

read_json_version() {
  jq -r '.version' "$1"
}

read_market_version() {
  local marketplace="$1" name="$2"
  jq -r --arg name "$name" '.plugins[] | select(.name == $name) | .version' "$marketplace"
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" != "$expected" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    fail "$label: missing '$needle'"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    fail "$label: unexpected '$needle'"
  fi
}

active_plugin_roots() {
  local source
  jq -r '.plugins[] | select(.source | startswith("./skills/")) | .source' "$ROOT/.claude-plugin/marketplace.json" |
    while IFS= read -r source; do
      printf '%s/%s\n' "$ROOT" "${source#./}"
    done | sort
}

read_frontmatter_name() {
  awk '
    /^name:[[:space:]]*/ {
      sub(/^name:[[:space:]]*/, "", $0)
      gsub(/^["'\''[:space:]]+|["'\''[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$1"
}

read_frontmatter_field() {
  local file="$1" field="$2"
  python3 - "$file" "$field" <<'PY'
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"{sys.argv[1]}: could not import yaml parser: {exc}")

path, field = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()

if not lines or lines[0].strip() != "---":
    raise SystemExit(f"{path}: missing YAML frontmatter")

end_idx = next((idx for idx, line in enumerate(lines[1:], start=1) if line.strip() == "---"), None)
if end_idx is None:
    raise SystemExit(f"{path}: missing YAML frontmatter terminator")

data = yaml.safe_load("\n".join(lines[1:end_idx])) or {}
value = data.get(field)
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(str(value))
PY
}

validate_skill_frontmatter() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"{sys.argv[1]}: could not import yaml parser: {exc}")

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()

if not lines or lines[0].strip() != "---":
    raise SystemExit(f"{path}: missing YAML frontmatter")

end_idx = next((idx for idx, line in enumerate(lines[1:], start=1) if line.strip() == "---"), None)
if end_idx is None:
    raise SystemExit(f"{path}: missing YAML frontmatter terminator")

frontmatter = "\n".join(lines[1:end_idx])

try:
    data = yaml.safe_load(frontmatter) or {}
except Exception as exc:
    raise SystemExit(f"{path}: invalid YAML: {exc}")

allowed = {
    "allowed-tools",
    "argument-hint",
    "compatibility",
    "description",
    "license",
    "metadata",
    "name",
    "user-invocable",
}
unexpected = sorted(set(data) - allowed)
if unexpected:
    raise SystemExit(f"{path}: unsupported frontmatter fields: {', '.join(unexpected)}")

description = str(data.get("description", ""))
if len(description) > 1024:
    raise SystemExit(f"{path}: invalid description: exceeds maximum length of 1024 characters")
PY
}

write_skill_fixture() {
  local repo="$1" skill="$2" version="$3" with_codex="$4"
  mkdir -p "$repo/skills/$skill/.claude-plugin"
  cat > "$repo/skills/$skill/SKILL.md" <<EOF
---
name: $skill
description: fixture
---
EOF
  cat > "$repo/skills/$skill/.claude-plugin/plugin.json" <<EOF
{
  "name": "$skill",
  "version": "$version"
}
EOF
  if [ "$with_codex" = "yes" ]; then
    mkdir -p "$repo/skills/$skill/.codex-plugin"
    cat > "$repo/skills/$skill/.codex-plugin/plugin.json" <<EOF
{
  "name": "$skill",
  "version": "$version"
}
EOF
  fi
}

run_bump_version_checks() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/scripts" "$tmp/.claude-plugin"
  cp "$ROOT/scripts/bump-version.sh" "$tmp/scripts/bump-version.sh"
  chmod +x "$tmp/scripts/bump-version.sh"

  write_skill_fixture "$tmp" "demo-codex" "1.2.3" "yes"
  write_skill_fixture "$tmp" "demo-basic" "0.4.0" "no"

  cat > "$tmp/.claude-plugin/marketplace.json" <<'EOF'
{
  "plugins": [
    {
      "name": "demo-codex",
      "version": "1.2.3"
    },
    {
      "name": "demo-basic",
      "version": "0.4.0"
    }
  ]
}
EOF

  local dry_run
  dry_run="$(cd "$tmp" && ./scripts/bump-version.sh demo-codex --set 1.2.4 --dry-run)"
  assert_contains "dry-run file list" "$dry_run" "skills/demo-codex/.codex-plugin/plugin.json"

  (cd "$tmp" && ./scripts/bump-version.sh demo-codex --set 1.2.4 >/dev/null)
  assert_eq "demo-codex Claude manifest" "$(read_json_version "$tmp/skills/demo-codex/.claude-plugin/plugin.json")" "1.2.4"
  assert_eq "demo-codex Codex manifest" "$(read_json_version "$tmp/skills/demo-codex/.codex-plugin/plugin.json")" "1.2.4"
  assert_eq "demo-codex marketplace" "$(read_market_version "$tmp/.claude-plugin/marketplace.json" demo-codex)" "1.2.4"

  (cd "$tmp" && ./scripts/bump-version.sh demo-basic --set 0.4.1 >/dev/null)
  assert_eq "demo-basic Claude manifest" "$(read_json_version "$tmp/skills/demo-basic/.claude-plugin/plugin.json")" "0.4.1"
  assert_eq "demo-basic marketplace" "$(read_market_version "$tmp/.claude-plugin/marketplace.json" demo-basic)" "0.4.1"
}

run_doctor_prompt_contract_checks() {
  local doctor
  doctor="$(cat "$ROOT/skills/dev-loop/agents/doctor-worker.md")"

  # These assert literal needles that must appear verbatim in the prompt — the
  # tildes and backticks are part of the text we grep for, not values to expand.
  # shellcheck disable=SC2088,SC2016
  assert_contains "doctor root Claude plugin skill path" "$doctor" '~/.claude/plugins/cache/*/<plugin>/*/SKILL.md'
  # shellcheck disable=SC2088
  assert_contains "doctor root Codex plugin skill path" "$doctor" '~/.codex/plugins/cache/*/<plugin>/*/SKILL.md'
  assert_contains "doctor wildcard agent probe" "$doctor" 'agents/*.md'
  # shellcheck disable=SC2016
  assert_contains "doctor frontmatter agent name match" "$doctor" 'frontmatter `name:`'
}

run_sync_script_contract_checks() {
  local sync_script
  sync_script="$(cat "$ROOT/skills/dev-loop/sync-plugin-cache.sh")"

  assert_contains "sync-plugin-cache includes dependencies manifest" "$sync_script" 'dependencies.yaml'
  assert_contains "sync-plugin-cache syncs Codex skills subtree" "$sync_script" 'Sync Codex skills subtree'
  assert_contains "sync-plugin-cache syncs agents directory" "$sync_script" 'Sync agents directory'
  assert_contains "sync-plugin-cache copies agents directory" "$sync_script" 'cp "${SOURCE_DIR}/agents/"* "${CACHE_DIR}/agents/"'
  assert_contains "sync-plugin-cache syncs scripts directory" "$sync_script" 'Sync scripts directory'
  assert_contains "sync-plugin-cache copies scripts recursively" "$sync_script" 'scripts/.'
  assert_contains "sync-plugin-cache syncs skill-relative references" "$sync_script" 'skills/dev-loop/references'
  [ -f "$ROOT/skills/dev-loop/agents/simplify-worker.md" ] ||
    fail "skills/dev-loop/agents/simplify-worker.md missing"
  [ -f "$ROOT/skills/dev-loop/skills/dev-loop/references/codex-tools.md" ] ||
    fail "skills/dev-loop/skills/dev-loop/references/codex-tools.md missing"
  cmp -s "$ROOT/skills/dev-loop/references/codex-tools.md" "$ROOT/skills/dev-loop/skills/dev-loop/references/codex-tools.md" ||
    fail "skills/dev-loop/skills/dev-loop/references/codex-tools.md differs from canonical reference"
}

run_simplify_worker_adapter_contract_checks() {
  local worker
  worker="$(cat "$ROOT/skills/dev-loop/agents/simplify-worker.md")"

  assert_contains "simplify-worker reads source skill" "$worker" 'read and follow'
  assert_contains "simplify-worker source of truth" "$worker" '`simplify:simplify` as the source of truth'
  assert_contains "simplify-worker optional path override" "$worker" '`simplify_skill_path` (optional)'
  assert_contains "simplify-worker Claude skill path" "$worker" '~/.claude/skills/simplify/simplify/SKILL.md'
  assert_contains "simplify-worker Codex skill path" "$worker" '~/.agents/skills/simplify/SKILL.md'
  assert_contains "simplify-worker Codex plugin cache path" "$worker" '~/.codex/plugins/cache/*/simplify/*/skills/simplify/SKILL.md'
  assert_contains "simplify-worker fallback trigger" "$worker" 'If no `simplify:simplify` SKILL.md can be resolved'
  assert_contains "simplify-worker scopes diff" "$worker" '### Scope the review'
  assert_contains "simplify-worker reuse pass" "$worker" '### Pass A: Reuse'
  assert_contains "simplify-worker quality pass" "$worker" '### Pass B: Quality'
  assert_contains "simplify-worker efficiency pass" "$worker" '### Pass C: Efficiency'
  assert_contains "simplify-worker report-only behavior" "$worker" 'Report-only behavior'
  assert_contains "simplify-worker preserves behavior" "$worker" 'Preserve behavior'
  assert_contains "simplify-worker validates" "$worker" '### Validate'
  assert_contains "simplify-worker file line output" "$worker" 'file:line references'
}

run_sdd_execute_worker_adapter_contract_checks() {
  local worker
  worker="$(cat "$ROOT/skills/dev-loop/agents/sdd-execute-worker.md")"

  assert_contains "sdd-execute-worker reads source skill" "$worker" 'read and follow'
  assert_contains "sdd-execute-worker source of truth" "$worker" '`superpowers:subagent-driven-development` as the source of truth'
  assert_contains "sdd-execute-worker optional path override" "$worker" '`execute_skill_path` (optional)'
  assert_contains "sdd-execute-worker Claude skill path" "$worker" '~/.claude/skills/superpowers/subagent-driven-development/SKILL.md'
  assert_contains "sdd-execute-worker Codex skill path" "$worker" '~/.agents/skills/superpowers/subagent-driven-development/SKILL.md'
  assert_contains "sdd-execute-worker Codex plugin cache path" "$worker" '~/.codex/plugins/cache/*/superpowers/*/skills/subagent-driven-development/SKILL.md'
  assert_contains "sdd-execute-worker fallback trigger" "$worker" 'If no `superpowers:subagent-driven-development` `SKILL.md` can be resolved'
  assert_contains "sdd-execute-worker sonnet rule" "$worker" '`model: "sonnet"` to every implementer, task-reviewer, and fix-subagent'
  assert_contains "sdd-execute-worker preserves caller scope" "$worker" 'Preserve caller scope'
  assert_contains "sdd-execute-worker source unavailable signal" "$worker" 'SOURCE_SKILL_UNAVAILABLE'
  assert_contains "sdd-execute-worker blocked signal" "$worker" 'BLOCKED: <reason>'
}

run_dev_loop_dependency_contract_checks() {
  python3 - "$ROOT/skills/dev-loop/dependencies.yaml" <<'PY'
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"{sys.argv[1]}: could not import yaml parser: {exc}")

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = []
for section in ("required", "optional"):
    section_entries = data.get(section) or []
    if not isinstance(section_entries, list):
        raise SystemExit(f"{path}: {section} must be a list")
    for entry in section_entries:
        if not isinstance(entry, dict):
            raise SystemExit(f"{path}: {section} contains a non-object entry")
        entries.append(entry)

by_ref = {}
for entry in entries:
    ref = entry.get("ref")
    if not ref:
        raise SystemExit(f"{path}: dependency entry missing ref: {entry!r}")
    if ref in by_ref:
        raise SystemExit(f"{path}: duplicate dependency ref: {ref}")
    by_ref[ref] = entry

def expect_entry(ref, expected, used_by):
    entry = by_ref.get(ref)
    if entry is None:
        raise SystemExit(f"{path}: missing dependency entry {ref}")
    for key, value in expected.items():
        if entry.get(key) != value:
            raise SystemExit(
                f"{path}: {ref}.{key} expected {value!r}, got {entry.get(key)!r}"
            )
    actual_used_by = entry.get("used_by")
    if actual_used_by != used_by:
        raise SystemExit(
            f"{path}: {ref}.used_by expected {used_by!r}, got {actual_used_by!r}"
        )

expect_entry(
    "simplify:simplify",
    {
        "kind": "skill",
        "capability": "code_review_gate",
        "fallback": "block code-changing cycle; no manual substitute for required simplify review",
    },
    ["REVIEW step 6 base backend", "Pre-push gate"],
)

expect_entry(
    "dev-loop:simplify-worker",
    {
        "kind": "agent",
        "capability": "code_review_gate_adapter",
        "fallback": "inline Skill('simplify:simplify')",
        "self": True,
    },
    ["REVIEW step 6 preferred subagent adapter for simplify:simplify"],
)

expect_entry(
    "dev-loop:sdd-execute-worker",
    {
        "kind": "agent",
        "capability": "execute_with_subagent_dispatch_adapter",
        "fallback": "inline Skill('superpowers:subagent-driven-development')",
        "self": True,
    },
    ["EXECUTE step 5 preferred subagent adapter for superpowers:subagent-driven-development"],
)
PY
}

run_dev_loop_prep_prompt_contract_checks() {
  local prompt template setup codex_ref
  prompt="$(cat "$ROOT/skills/dev-loop/SKILL.md")"
  template="$(cat "$ROOT/skills/dev-loop/templates/project-config.md")"
  setup="$(cat "$ROOT/skills/dev-loop/setup-dev-loop/SKILL.md")"
  codex_ref="$(cat "$ROOT/skills/dev-loop/references/codex-tools.md")"

  assert_contains "dev-loop parses prep mode" "$prompt" 'MODE = prep'
  assert_contains "dev-loop dispatches prep mode" "$prompt" '**`prep`**'
  assert_contains "dev-loop references preflight inventory helper" "$prompt" 'preflight-inventory.js'
  assert_contains "dev-loop status mode documented" "$prompt" 'MODE = status'
  assert_contains "dev-loop status pipeline" "$prompt" 'Status pipeline'
  assert_contains "dev-loop status helper script" "$prompt" 'dev-loop-status.js'
  assert_contains "dev-loop status HUD helper" "$prompt" 'dev-loop-status-hud.js'
  assert_contains "dev-loop status-worker agent doc" "$prompt" 'dev-loop:status-worker'
  [ -f "$ROOT/skills/dev-loop/agents/status-worker.md" ] ||
    fail "skills/dev-loop/agents/status-worker.md missing"
  assert_contains "status-worker read-only contract" "$(cat "$ROOT/skills/dev-loop/agents/status-worker.md")" 'writes_executed === false'
  assert_contains "codex reference documents status-worker" "$codex_ref" 'dev-loop:status-worker'
  assert_contains "dev-loop config-lint mode" "$prompt" 'MODE = config-lint'
  assert_contains "dev-loop config-lint script" "$prompt" 'dev-loop-config-lint.js'
  assert_contains "dev-loop config migrate script" "$prompt" 'dev-loop-config-migrate.js'
  assert_contains "dev-loop dashboard script" "$prompt" 'dev-loop-dashboard.js'
  assert_contains "dev-loop dashboard mode" "$prompt" 'MODE = dashboard'
  assert_contains "dev-loop why-skipped script" "$prompt" 'dev-loop-why-skipped.js'
  assert_contains "dev-loop status read-only deny" "$prompt" 'Read-only deny-list'
  assert_contains "dev-loop resolves preflight policy" "$prompt" 'PREFLIGHT_POLICY'
  assert_contains "dev-loop gates automation readiness" "$prompt" 'automation_ready'
  assert_contains "dev-loop reports readiness skips" "$prompt" 'Automation Readiness Skips'
  assert_contains "dev-loop prep never starts goal" "$prompt" 'Do not start `/goal`'

  assert_contains "project config includes preflight block" "$template" 'preflight:'
  assert_contains "project config includes unattended skip behavior" "$template" 'unattended_not_ready_behavior: skip'
  assert_contains "project config includes readiness state" "$template" 'preflight_state: ready'
  assert_contains "project config requires simplify base skill" "$template" 'The base `simplify:simplify`'
  assert_contains "project config simplify always runs" "$template" 'skill always runs for code changes'
  assert_contains "project config prefers simplify-worker" "$template" '`dev-loop:simplify-worker` subagent adapter when worker dispatch is available'
  assert_contains "project config inline simplify fallback" "$template" 'inline `Skill("simplify:simplify")` when worker dispatch'

  assert_contains "project config uses portable skillwiki vault auto" "$template" 'vault: auto'
  assert_contains "project config documents legacy top-level vault alias" "$template" 'Legacy top-level `vault` is still supported as an alias'
  assert_contains "dev-loop documents vault auto resolution" "$prompt" '`vault: auto`'
  assert_contains "dev-loop documents skillwiki path precedence" "$prompt" 'run `skillwiki path`'
  assert_contains "dev-loop documents validated wiki fallback" "$prompt" 'validated `~/wiki` fallback'
  assert_contains "dev-loop documents explicit vault mismatch warning" "$prompt" 'Configured SkillWiki vault'

  assert_contains "dev-loop requires simplify skill review" "$prompt" '**REQUIRED SUB-SKILL:** Use `simplify:simplify`'
  assert_contains "dev-loop prefers simplify-worker adapter" "$prompt" 'Default to the `dev-loop:simplify-worker` subagent adapter'
  assert_contains "dev-loop inline simplify is fallback" "$prompt" 'inline `Skill("simplify:simplify")` only when'
  assert_contains "setup documents simplify worker preference" "$setup" 'prefer `dev-loop:simplify-worker` for subagent isolation'
  assert_contains "codex reference documents multi-agent gate" "$codex_ref" 'multi_agent = true'
  assert_contains "codex reference maps spawn_agent task name" "$codex_ref" '`Agent(subagent_type=X, model=…)` (spawn worker) | `spawn_agent(task_name=X, prompt=...)`'
  assert_contains "codex reference documents simplify-worker adapter" "$codex_ref" '`dev-loop:simplify-worker` | REVIEW step 6 | preferred isolated adapter for `simplify:simplify`'
  assert_contains "codex reference documents sdd-execute-worker adapter" "$codex_ref" '`dev-loop:sdd-execute-worker` | EXECUTE step 5 | preferred isolated adapter for `superpowers:subagent-driven-development`'
  assert_contains "dev-loop prompt documents sdd-execute-worker adapter" "$prompt" 'superpowers:subagent-driven-development (prefer `dev-loop:sdd-execute-worker` when worker dispatch is available)'
  assert_not_contains "dev-loop no stale simplify-worker base backend" "$prompt" 'Always include `dev-loop:simplify-worker` (base backend)'
  assert_not_contains "setup no stale simplify-worker base backend" "$setup" 'Always includes `dev-loop:simplify-worker`'
  assert_not_contains "template no stale simplify-worker base backend" "$template" 'backend (`dev-loop:simplify-worker`) always runs'
}

run_dev_loop_status_companion_contract_checks() {
  local skill_root canonical mirror sync_script
  skill_root="$ROOT/skills/dev-loop"
  canonical="$skill_root/status/SKILL.md"
  mirror="$skill_root/skills/status/SKILL.md"
  [ -f "$canonical" ] || fail "${canonical#$ROOT/} missing"
  [ -f "$mirror" ] || fail "${mirror#$ROOT/} missing"
  cmp -s "$canonical" "$mirror" || fail "dev-loop status companion mirror differs from canonical"
  sync_script="$(cat "$skill_root/sync-plugin-cache.sh")"
  assert_contains "sync-plugin-cache syncs status companion" "$sync_script" 'status/SKILL.md'
  assert_contains "dev-loop status companion deny-list" "$(cat "$canonical")" 'Hard deny-list'
  assert_contains "dev-loop references status companion" "$(cat "$skill_root/SKILL.md")" 'status/SKILL.md'
  assert_contains "status companion HUD section" "$(cat "$canonical")" 'dev-loop-status-hud.js'
}

run_dev_loop_command_surface_contract_checks() {
  local skill_root umbrella umbrella_mirror hint helper helper_mirror body helper_body
  local helper_name helper_field helper_hint

  skill_root="$ROOT/skills/dev-loop"
  umbrella="$skill_root/SKILL.md"
  umbrella_mirror="$skill_root/skills/dev-loop/SKILL.md"

  cmp -s "$umbrella" "$umbrella_mirror" ||
    fail "dev-loop mirrored SKILL.md differs from canonical"

  hint="$(read_frontmatter_field "$umbrella" "argument-hint")"
  [ -n "$hint" ] || fail "dev-loop umbrella SKILL.md missing argument-hint"
  assert_contains "dev-loop argument hint includes status" "$hint" "status"
  assert_contains "dev-loop argument hint includes doctor" "$hint" "doctor"
  assert_contains "dev-loop argument hint includes investigate" "$hint" "investigate"
  assert_contains "dev-loop argument hint includes office-hours" "$hint" "office-hours"
  assert_contains "dev-loop argument hint includes setup" "$hint" "setup"
  assert_contains "dev-loop argument hint includes setup-dev-loop" "$hint" "setup-dev-loop"
  assert_contains "dev-loop argument hint includes config-lint" "$hint" "config-lint"
  assert_contains "dev-loop argument hint includes dashboard" "$hint" "dashboard"

  body="$(cat "$umbrella")"
  assert_contains "dev-loop parses office-hours mode" "$body" "MODE = office-hours"
  assert_contains "dev-loop parses setup mode" "$body" "MODE = setup"
  assert_contains "dev-loop setup-dev-loop alias" "$body" "setup-dev-loop"
  assert_contains "dev-loop standard office-hours example" "$body" "/dev-loop office-hours"
  assert_contains "dev-loop standard setup example" "$body" "/dev-loop setup"
  assert_contains "dev-loop standard Codex entrypoint" "$body" '$dev-loop'
  assert_not_contains "dev-loop does not expose research mode" "$body" "/dev-loop research"
  assert_not_contains "dev-loop parent no status colon command" "$body" "/dev-loop:status"
  assert_not_contains "dev-loop parent no investigate colon command" "$body" "/dev-loop:investigate"
  assert_not_contains "dev-loop parent no office-hours colon command" "$body" "/dev-loop:office-hours"
  assert_not_contains "dev-loop parent no research colon command" "$body" "/dev-loop:research"
  assert_not_contains "dev-loop parent no setup colon command" "$body" "/dev-loop:setup-dev-loop"

  for helper_name in status investigate office-hours research setup-dev-loop; do
    helper="$skill_root/$helper_name/SKILL.md"
    helper_mirror="$skill_root/skills/$helper_name/SKILL.md"
    [ -f "$helper" ] || fail "${helper#$ROOT/} missing"
    [ -f "$helper_mirror" ] || fail "${helper_mirror#$ROOT/} missing"
    cmp -s "$helper" "$helper_mirror" ||
      fail "${helper_mirror#$ROOT/} differs from ${helper#$ROOT/}"

    helper_field="$(read_frontmatter_field "$helper" "user-invocable")"
    assert_eq "$helper_name user-invocable" "$helper_field" "false"

    helper_hint="$(read_frontmatter_field "$helper" "argument-hint")"
    assert_eq "$helper_name argument-hint" "$helper_hint" ""

    helper_body="$(cat "$helper")"
    assert_not_contains "$helper_name no Claude colon command docs" "$helper_body" "/dev-loop:$helper_name"
    assert_not_contains "$helper_name no Codex colon command docs" "$helper_body" '$dev-loop:'"$helper_name"
  done
}

run_dev_loop_office_hours_contract_checks() {
  local skill_root canonical mirror body sync_script

  skill_root="$ROOT/skills/dev-loop"
  canonical="$skill_root/office-hours/SKILL.md"
  mirror="$skill_root/skills/office-hours/SKILL.md"

  [ -f "$canonical" ] || fail "${canonical#$ROOT/} missing"
  [ -f "$mirror" ] || fail "${mirror#$ROOT/} missing"
  cmp -s "$canonical" "$mirror" || fail "${mirror#$ROOT/} differs from ${canonical#$ROOT/}"

  body="$(cat "$canonical")"
  sync_script="$(cat "$skill_root/sync-plugin-cache.sh")"

  assert_contains "office-hours uses inventory helper" "$body" 'preflight-inventory.js'
  assert_contains "office-hours documents all-projects input" "$body" '/dev-loop office-hours --all-projects'
  assert_not_contains "office-hours no colon command example" "$body" '/dev-loop:office-hours'
  assert_contains "office-hours documents all-projects helper flag" "$body" '  --all-projects --vault <vault> --limit <n>'
  assert_contains "office-hours documents project repo metadata" "$body" 'project-repos.yaml'
  assert_contains "office-hours documents vault-only cross-project discovery" "$body" 'Cross-project discovery is vault-only'
  assert_contains "office-hours resolves repo after project selection" "$body" 'resolve the selected project repository'
  assert_contains "office-hours documents no remote SSH evidence" "$body" 'Office-hours v1 does not SSH'
  assert_contains "office-hours documents degraded unresolved status" "$body" '`unresolved`'
  assert_contains "office-hours documents degraded ambiguous status" "$body" '`ambiguous`'
  assert_contains "office-hours documents degraded wrong remote status" "$body" '`wrong_remote`'
  assert_contains "office-hours documents degraded host unknown status" "$body" '`host_unknown`'
  assert_contains "office-hours groups cross-project candidates by slug" "$body" 'grouped by `project_slug`'
  assert_contains "office-hours reports selected project slug" "$body" 'record the selected `project_slug`'
  assert_contains "office-hours refreshes memory index" "$body" 'skillwiki memory index'
  assert_contains "office-hours lists memory topics" "$body" 'skillwiki memory topics'
  assert_contains "office-hours reads project index" "$body" 'skillwiki project-index'
  assert_contains "office-hours report path contract" "$body" 'projects/<slug>/requirements/YYYY-MM-DD-office-hours-<topic>.md'
  assert_contains "office-hours no raw mutation rule" "$body" 'Do NOT modify raw transcripts'
  assert_contains "office-hours no automatic promotion rule" "$body" 'Do NOT auto-create planned work'
  assert_contains "office-hours no preflight readiness rule" "$body" 'Do NOT set preflight readiness'
  assert_contains "office-hours no goal lifecycle rule" "$body" 'Do NOT start or manage `/goal`'
  assert_contains "office-hours Claude structured questions" "$body" 'AskUserQuestion'
  assert_contains "office-hours Codex request_user_input mapping" "$body" 'Codex CLI or Codex App | `request_user_input` in Codex Plan mode; numbered conversational fallback in Codex Default mode'
  assert_contains "office-hours Codex live tool probe" "$body" 'Probe the live tool surface before calling a structured question tool'
  assert_contains "office-hours Codex Plan-mode gate" "$body" 'In Codex App/CLI, use `request_user_input` only in Plan mode when the tool is exposed'
  assert_contains "office-hours Codex Default fallback" "$body" 'In Codex Default mode, do not call it; use conversational fallback'
  assert_not_contains "office-hours no stale Codex ask_user_question mapping" "$body" 'Codex CLI or Codex App | `ask_user_question`'
  assert_contains "office-hours Antigravity structured questions" "$body" 'ask_question'
  assert_contains "office-hours conversational fallback" "$body" 'conversational fallback'
  assert_contains "office-hours prompts in main session only" "$body" 'main session only'
  assert_contains "office-hours forbids subagent prompts" "$body" 'Do NOT call structured question tools from subagents'
  assert_contains "office-hours stale implemented recheck" "$body" 'possibly_implemented_without_closure'
  assert_contains "office-hours stale handling remains human-controlled" "$body" 'hygiene-cleanup'
  assert_contains "office-hours optional grill hook" "$body" 'grill-me'
  assert_contains "sync-plugin-cache syncs office-hours companion" "$sync_script" 'office-hours/SKILL.md'
}

run_dev_loop_investigate_queue_contract_checks() {
  local canonical mirror prompt prompt_mirror

  canonical="$(cat "$ROOT/skills/dev-loop/investigate/SKILL.md")"
  mirror="$(cat "$ROOT/skills/dev-loop/skills/investigate/SKILL.md")"
  prompt="$(cat "$ROOT/skills/dev-loop/SKILL.md")"
  prompt_mirror="$(cat "$ROOT/skills/dev-loop/skills/dev-loop/SKILL.md")"

  cmp -s "$ROOT/skills/dev-loop/investigate/SKILL.md" "$ROOT/skills/dev-loop/skills/investigate/SKILL.md" ||
    fail "dev-loop mirrored investigate SKILL.md differs from canonical"
  cmp -s "$ROOT/skills/dev-loop/SKILL.md" "$ROOT/skills/dev-loop/skills/dev-loop/SKILL.md" ||
    fail "dev-loop mirrored SKILL.md differs from canonical"

  assert_contains "investigate uses disposable schema probe" "$canonical" 'disposable schema-probe candidate'
  assert_contains "investigate mirror uses disposable schema probe" "$mirror" 'disposable schema-probe candidate'
  assert_contains "investigate documents current-schema raw fallback" "$canonical" 'Current SkillWiki schemas such as 0.9.16 reject `status: proposed`'
  assert_contains "investigate mirror documents current-schema raw fallback" "$mirror" 'Current SkillWiki schemas such as 0.9.16 reject `status: proposed`'
  assert_contains "dev-loop summary documents current-schema raw fallback" "$prompt" 'Current SkillWiki schemas such as 0.9.16 reject `status: proposed`'
  assert_contains "dev-loop mirror summary documents current-schema raw fallback" "$prompt_mirror" 'Current SkillWiki schemas such as 0.9.16 reject `status: proposed`'
  assert_not_contains "investigate no durable proposed workdir probe" "$canonical" 'Draft a single candidate non-executing work item in the target project'
  assert_not_contains "investigate mirror no durable proposed workdir probe" "$mirror" 'Draft a single candidate non-executing work item in the target project'
}

run_codex_dispatch_contract_checks() {
  local skill canonical_ref
  skill="$(cat "$ROOT/skills/dev-loop/SKILL.md")"
  canonical_ref="$(cat "$ROOT/skills/dev-loop/references/codex-tools.md")"

  cmp -s "$ROOT/skills/dev-loop/SKILL.md" "$ROOT/skills/dev-loop/skills/dev-loop/SKILL.md" ||
    fail "dev-loop mirrored SKILL.md differs from canonical"
  cmp -s "$ROOT/skills/dev-loop/references/codex-tools.md" "$ROOT/skills/dev-loop/skills/dev-loop/references/codex-tools.md" ||
    fail "dev-loop mirrored codex-tools.md differs from canonical"

  assert_not_contains "dev-loop SKILL Codex spawn argument" "$skill" 'spawn_agent(agent_name='
  assert_not_contains "dev-loop codex-tools Codex spawn argument" "$canonical_ref" 'spawn_agent(agent_name='
  assert_contains "dev-loop SKILL Codex task_name example" "$skill" 'spawn_agent(task_name="doctor-worker"'
  assert_contains "dev-loop codex-tools task_name mapping" "$canonical_ref" 'task_name'
  assert_contains "dev-loop SKILL instruction-level dispatch wording" "$skill" 'instruction-level dispatch'
  assert_contains "dev-loop codex-tools custom agent TOML location" "$canonical_ref" '.codex/agents/'
}

assert_json_array_contains() {
  local label="$1" file="$2" jq_filter="$3" expected="$4"
  if ! jq -e --arg expected "$expected" "$jq_filter | index(\$expected) != null" "$file" >/dev/null; then
    fail "$label: missing '$expected'"
  fi
}

run_dev_loop_metadata_contract_checks() {
  local skill_root skill_version claude_manifest codex_manifest marketplace
  local claude_description codex_description marketplace_description
  local setup_source setup_mirror

  skill_root="$ROOT/skills/dev-loop"
  claude_manifest="$skill_root/.claude-plugin/plugin.json"
  codex_manifest="$skill_root/.codex-plugin/plugin.json"
  marketplace="$ROOT/.claude-plugin/marketplace.json"
  skill_version="$(read_json_version "$claude_manifest")"

  assert_eq "dev-loop Claude manifest version" "$(read_json_version "$claude_manifest")" "$skill_version"
  assert_eq "dev-loop Codex manifest version" "$(read_json_version "$codex_manifest")" "$skill_version"
  assert_eq "dev-loop marketplace version" "$(read_market_version "$marketplace" dev-loop)" "$skill_version"

  claude_description="$(jq -r '.description' "$claude_manifest")"
  codex_description="$(jq -r '.description' "$codex_manifest")"
  marketplace_description="$(jq -r '.plugins[] | select(.name == "dev-loop") | .description' "$marketplace")"

  assert_contains "dev-loop SKILL.md current version headline" "$(cat "$skill_root/SKILL.md")" "v${skill_version}:"
  assert_contains "dev-loop Claude manifest current version headline" "$claude_description" "v${skill_version}:"
  assert_contains "dev-loop Codex manifest current version headline" "$codex_description" "v${skill_version}:"
  assert_contains "dev-loop marketplace current version headline" "$marketplace_description" "v${skill_version}:"

  assert_contains "dev-loop Claude manifest mentions prep mode" "$claude_description" "preflight prep mode"
  assert_contains "dev-loop Codex manifest mentions prep mode" "$codex_description" "preflight prep mode"
  assert_contains "dev-loop marketplace mentions prep mode" "$marketplace_description" "preflight prep mode"

  assert_json_array_contains "dev-loop Claude manifest prep keyword" "$claude_manifest" ".keywords" "prep"
  assert_json_array_contains "dev-loop Claude manifest preflight keyword" "$claude_manifest" ".keywords" "preflight"
  assert_json_array_contains "dev-loop Codex manifest prep keyword" "$codex_manifest" ".keywords" "prep"
  assert_json_array_contains "dev-loop Codex manifest preflight keyword" "$codex_manifest" ".keywords" "preflight"
  assert_json_array_contains "dev-loop marketplace prep keyword" "$marketplace" '.plugins[] | select(.name == "dev-loop") | .keywords' "prep"
  assert_json_array_contains "dev-loop marketplace preflight keyword" "$marketplace" '.plugins[] | select(.name == "dev-loop") | .keywords' "preflight"

  setup_source="$skill_root/setup-dev-loop/SKILL.md"
  setup_mirror="$skill_root/skills/setup-dev-loop/SKILL.md"
  [ -f "$setup_mirror" ] || fail "${setup_mirror#$ROOT/} missing setup-dev-loop Codex mirror"
  cmp -s "$setup_source" "$setup_mirror" || fail "${setup_mirror#$ROOT/} differs from ${setup_source#$ROOT/}"
}

run_agent_plugin_porter_release_workflow_contract_checks() {
  local skill_root canonical mirror canonical_body mirror_body version

  skill_root="$ROOT/skills/agent-plugin-porter"
  canonical="$skill_root/SKILL.md"
  mirror="$skill_root/skills/agent-plugin-porter/SKILL.md"
  version="$(read_json_version "$skill_root/.claude-plugin/plugin.json")"

  [ -f "$canonical" ] || fail "${canonical#$ROOT/} missing"
  [ -f "$mirror" ] || fail "${mirror#$ROOT/} missing"

  canonical_body="$(cat "$canonical")"
  mirror_body="$(cat "$mirror")"

  assert_contains "agent-plugin-porter SKILL.md release workflow heading" "$canonical_body" "## GitHub Release Workflow"
  assert_contains "agent-plugin-porter SKILL.md contents permission" "$canonical_body" "contents: write"
  assert_contains "agent-plugin-porter SKILL.md oidc permission" "$canonical_body" "id-token: write"
  assert_contains "agent-plugin-porter SKILL.md GitHub token" "$canonical_body" 'GH_TOKEN: ${{ github.token }}'
  assert_contains "agent-plugin-porter SKILL.md idempotent release check" "$canonical_body" 'gh release view "$GITHUB_REF_NAME"'
  assert_contains "agent-plugin-porter SKILL.md release create" "$canonical_body" 'gh release create "$GITHUB_REF_NAME" --generate-notes --title "$GITHUB_REF_NAME"'
  assert_contains "agent-plugin-porter SKILL.md missing release remediation" "$canonical_body" 'gh release create vX.Y.Z --repo <owner>/<repo> --title "vX.Y.Z" --generate-notes'

  assert_contains "agent-plugin-porter mirror release workflow heading" "$mirror_body" "## GitHub Release Workflow"
  assert_contains "agent-plugin-porter current version" "$version" "0.2.0"
}

run_deep_research_freshness_contract_checks() {
  local skill_root canonical mirror agent canonical_body mirror_body agent_body

  skill_root="$ROOT/skills/deep-research"
  canonical="$skill_root/SKILL.md"
  mirror="$skill_root/skills/deep-research/SKILL.md"
  agent="$skill_root/agents/deep-research.md"

  [ -f "$canonical" ] || fail "${canonical#$ROOT/} missing"
  [ -f "$mirror" ] || fail "${mirror#$ROOT/} missing"
  [ -f "$agent" ] || fail "${agent#$ROOT/} missing"

  canonical_body="$(cat "$canonical")"
  mirror_body="$(cat "$mirror")"
  agent_body="$(cat "$agent")"

  assert_contains "deep-research source triage" "$canonical_body" "Phase 1.5: Source Triage"
  assert_contains "deep-research grok-search freshness" "$canonical_body" "grok-search"
  assert_contains "deep-research freshness status section" "$canonical_body" "Freshness & Verification Status"
  assert_contains "deep-research key claims table" "$canonical_body" "| Claim | Status | Source route | Notes |"
  assert_contains "deep-research local inline triage" "$canonical_body" "local triage inline"
  assert_contains "deep-research mirror source triage" "$mirror_body" "Phase 1.5: Source Triage"

  assert_contains "deep-research agent source triage" "$agent_body" "Phase 1.5: Source Triage"
  assert_contains "deep-research agent grok-search freshness" "$agent_body" "grok-search"
  assert_contains "deep-research agent freshness status section" "$agent_body" "Freshness & Verification Status"
  assert_contains "deep-research agent local inline triage" "$agent_body" "local triage inline"
  assert_not_contains "deep-research agent no mandatory web search" "$agent_body" "always spawn at least 1"
}

run_skill_frontmatter_contract_checks() {
  while IFS= read -r skill; do
    validate_skill_frontmatter "$ROOT/$skill"
  done < <(
    cd "$ROOT" && find skills -maxdepth 4 -type f -name SKILL.md \
      -not -path '*/skills/*' \
      -print | sort
  )
}

run_plugin_version_sync_contract_checks() {
  local name version source root claude_manifest codex_manifest

  while IFS=$'\t' read -r name version source; do
    root="$ROOT/${source#./}"
    claude_manifest="$root/.claude-plugin/plugin.json"
    codex_manifest="$root/.codex-plugin/plugin.json"

    [ -d "$root" ] || fail "$name source directory missing: $source"
    [ -f "$claude_manifest" ] || fail "$name missing Claude plugin manifest"

    assert_eq "$name Claude manifest name" "$(jq -r '.name' "$claude_manifest")" "$name"
    assert_eq "$name Claude manifest version" "$(read_json_version "$claude_manifest")" "$version"

    if [ -f "$codex_manifest" ]; then
      assert_eq "$name Codex manifest name" "$(jq -r '.name' "$codex_manifest")" "$name"
      assert_eq "$name Codex manifest version" "$(read_json_version "$codex_manifest")" "$version"
    fi
  done < <(
    jq -r '.plugins[] | select(.source | startswith("./skills/")) | [.name, .version, .source] | @tsv' \
      "$ROOT/.claude-plugin/marketplace.json" | sort
  )
}

run_marketplace_inventory_contract_checks() {
  local root name source count version marketplace_version

  while IFS= read -r root; do
    name="$(jq -r '.name' "$root/.claude-plugin/plugin.json")"
    version="$(read_json_version "$root/.claude-plugin/plugin.json")"
    source="./skills/${root##*/}"

    count="$(
      jq -r --arg name "$name" '[.plugins[] | select(.name == $name)] | length' \
        "$ROOT/.claude-plugin/marketplace.json"
    )"
    assert_eq "$name root marketplace entry count" "$count" "1"

    assert_eq "$name root marketplace source" "$(
      jq -r --arg name "$name" '.plugins[] | select(.name == $name) | .source' \
        "$ROOT/.claude-plugin/marketplace.json"
    )" "$source"

    marketplace_version="$(read_market_version "$ROOT/.claude-plugin/marketplace.json" "$name")"
    assert_eq "$name root marketplace version" "$marketplace_version" "$version"
  done < <(
    find "$ROOT/skills" -mindepth 3 -maxdepth 3 -type f \
      -path '*/.claude-plugin/plugin.json' -print0 |
      xargs -0 -n1 dirname |
      xargs -n1 dirname |
      sort
  )
}

run_plugin_manifest_contract_checks() {
  local manifest rel root skills_path type

  while IFS= read -r manifest; do
    rel="${manifest#$ROOT/}"
    type="$(jq -r '.skills | type' "$manifest")"
    assert_eq "$rel skills field type" "$type" "string"
  done < <(
    find "$ROOT/skills" -maxdepth 3 -type f \
      \( -path '*/.codex-plugin/plugin.json' -o -path '*/.claude-plugin/plugin.json' \) \
      -print | sort
  )

  while IFS= read -r root; do
    manifest="$root/.codex-plugin/plugin.json"
    rel="${manifest#$ROOT/}"
    [ -f "$manifest" ] || fail "$rel missing"
    skills_path="$(jq -r '.skills // empty' "$manifest")"
    assert_eq "$rel skills path" "$skills_path" "./skills/"
  done < <(active_plugin_roots)
}

run_codex_skill_mirror_contract_checks() {
  local root canonical name mirror

  while IFS= read -r root; do
    while IFS= read -r canonical; do
      name="$(read_frontmatter_name "$canonical")"
      [ -n "$name" ] || fail "${canonical#$ROOT/} missing frontmatter name"
      mirror="$root/skills/$name/SKILL.md"
      [ -f "$mirror" ] || fail "${mirror#$ROOT/} missing mirror for ${canonical#$ROOT/}"
      cmp -s "$canonical" "$mirror" || fail "${mirror#$ROOT/} differs from ${canonical#$ROOT/}"
    done < <(
      find "$root" -maxdepth 3 -type f -name SKILL.md \
        -not -path "$root/skills/*" \
        -print | sort
    )
  done < <(active_plugin_roots)
}

run_bump_version_checks
run_doctor_prompt_contract_checks
run_sync_script_contract_checks
run_simplify_worker_adapter_contract_checks
run_sdd_execute_worker_adapter_contract_checks
run_dev_loop_dependency_contract_checks
run_dev_loop_prep_prompt_contract_checks
run_dev_loop_status_companion_contract_checks
run_dev_loop_command_surface_contract_checks
run_dev_loop_office_hours_contract_checks
run_dev_loop_investigate_queue_contract_checks
run_codex_dispatch_contract_checks
run_dev_loop_metadata_contract_checks
run_agent_plugin_porter_release_workflow_contract_checks
run_deep_research_freshness_contract_checks
run_skill_frontmatter_contract_checks
run_marketplace_inventory_contract_checks
run_plugin_version_sync_contract_checks
run_plugin_manifest_contract_checks
run_codex_skill_mirror_contract_checks

bash "$ROOT/scripts/test-dev-loop-status.sh"
bash "$ROOT/scripts/test-dev-loop-config-migrate.sh"
bash "$ROOT/scripts/test-dev-loop-dashboard.sh"

printf 'test-dev-loop-release-tooling: ok\n'
