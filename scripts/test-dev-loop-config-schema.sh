#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$ROOT/skills/dev-loop/scripts/dev-loop-config-schema.py"

fail() {
  printf 'test-dev-loop-config-schema: %s\n' "$1" >&2
  exit 1
}

[[ -f "$SCHEMA" ]] || fail "missing skills/dev-loop/scripts/dev-loop-config-schema.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/merged.md" <<'EOF'
# Parser contract

The first block establishes defaults that the second block overrides selectively.

```yaml
slug: "first slug"
release_branch: "main"
knowledge_backends:
  skillwiki:
    vault: "/srv/wiki"
    cli_entry: "skillwiki"
prd_backends:
  superpowers:
    capabilities:
      - execute
      - subagent_dispatch
    skills:
      execute: "superpowers:subagent-driven-development"
prd_disciplines:
  - skill: "superpowers:test-driven-development"
    when: "execute"
    mode: "mandatory"
    include_paths:
      - "skills/**"
e2e_scripts:
  - "bash scripts/first.sh"
  - "bash scripts/second.sh"
browser_verification:
  enabled: true
  trigger:
    - "apps/**/*.tsx"
  driver: "playwright-cli"
code_review:
  parallel: true
  codex:
    enabled_in_normal: false
    enabled_in_high: true
    agent: "dev-loop:codex-review-worker"
release_policy:
  auto_bump: false
  channel: "stable"
  trigger_globs:
    - "skills/**"
    - "scripts/**"
merge_policy:
  strategy: "repo-policy"
  auto_merge: false
  merge_method: "squash"
  require_work_item_approval: true
```

The next block keeps the surrounding maps while replacing selected values.

```yml
slug: "winning slug"
knowledge_backends:
  skillwiki:
    vault: "auto"
prd_backends:
  superpowers:
    capabilities:
      - execute
      - review
prd_disciplines:
  - skill: "superpowers:systematic-debugging"
    when: "failure"
    mode: "reactive"
e2e_scripts:
  - "bash scripts/final.sh"
browser_verification:
  trigger:
    - "apps/**/*.css"
code_review:
  codex:
    enabled_in_normal: true
release_policy:
  auto_bump: true
  trigger_globs:
    - "src/**"
merge_policy:
  auto_merge: true
```
EOF

cat > "$TMP/unknown-keys.md" <<'EOF'
# Unknown keys

```yaml
slug: known
mystery_mode: true
knowledge_backends:
  skillwiki:
    vault: auto
    mystery_option: true
```
EOF

cat > "$TMP/malformed.md" <<'EOF'
# Malformed YAML

```yaml
merge_policy:
  strategy: "bad\q"
```
EOF

cat > "$TMP/unfenced.md" <<'EOF'
# Unfenced configuration

slug: escaped-config
EOF

cat > "$TMP/ordinary-prose.md" <<'EOF'
# Ordinary Markdown

The release policy: remains a human decision until the review is complete.

- Review the release policy before publishing.
- Keep the branch stable and documented.
EOF

assert_contract_fields() {
  local output="$1"
  node - "$output" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const field of ["config", "provenance", "blocks", "errors", "warnings", "parser"]) {
  assert.ok(Object.hasOwn(result, field), `missing contract field: ${field}`);
}
assert.equal(typeof result.config, "object", "config must be an object");
assert.equal(typeof result.provenance, "object", "provenance must be an object");
assert.ok(Array.isArray(result.blocks), "blocks must be an array");
assert.ok(Array.isArray(result.errors), "errors must be an array");
assert.ok(Array.isArray(result.warnings), "warnings must be an array");
assert.equal(typeof result.parser, "object", "parser capability metadata must be an object");
NODE
}

run_rejected() {
  local label="$1" output="$2" error_output="$3"
  shift 3
  local status
  set +e
  "$@" >"$output" 2>"$error_output"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$label fixture must exit nonzero"
  [[ -s "$output" ]] || fail "$label fixture must emit JSON on stdout"
  [[ ! -s "$error_output" ]] || fail "$label fixture wrote unstructured stderr"
  assert_contract_fields "$output"
}

MERGED_OUT="$TMP/merged.json"
python3 "$SCHEMA" --file "$TMP/merged.md" >"$MERGED_OUT" ||
  fail "valid merge fixture was rejected"
assert_contract_fields "$MERGED_OUT"
node - "$MERGED_OUT" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
assert.deepEqual(result.config, {
  slug: "winning slug",
  release_branch: "main",
  knowledge_backends: {
    skillwiki: {
      vault: "auto",
      cli_entry: "skillwiki",
    },
  },
  prd_backends: {
    superpowers: {
      capabilities: ["execute", "review"],
      skills: {
        execute: "superpowers:subagent-driven-development",
      },
    },
  },
  prd_disciplines: [
    {
      skill: "superpowers:systematic-debugging",
      when: "failure",
      mode: "reactive",
    },
  ],
  e2e_scripts: ["bash scripts/final.sh"],
  browser_verification: {
    enabled: true,
    trigger: ["apps/**/*.css"],
    driver: "playwright-cli",
  },
  code_review: {
    parallel: true,
    codex: {
      enabled_in_normal: true,
      enabled_in_high: true,
      agent: "dev-loop:codex-review-worker",
    },
  },
  release_policy: {
    auto_bump: true,
    channel: "stable",
    trigger_globs: ["src/**"],
  },
  merge_policy: {
    strategy: "repo-policy",
    auto_merge: true,
    merge_method: "squash",
    require_work_item_approval: true,
  },
});
assert.deepEqual(result.errors, []);
assert.deepEqual(result.warnings, []);
assert.equal(result.parser.name, "pyyaml");
assert.equal(result.parser.available, true);
assert.equal(typeof result.parser.version, "string");
assert.ok(result.parser.version.length > 0, "parser version must be populated");

const expectedProvenance = {
  slug: { block_index: 1, line: 55 },
  "knowledge_backends.skillwiki.vault": { block_index: 1, line: 58 },
  "knowledge_backends.skillwiki.cli_entry": { block_index: 0, line: 11 },
  "prd_backends.superpowers.capabilities": { block_index: 1, line: 61 },
  "prd_backends.superpowers.skills.execute": { block_index: 0, line: 18 },
  prd_disciplines: { block_index: 1, line: 64 },
  e2e_scripts: { block_index: 1, line: 68 },
  "browser_verification.trigger": { block_index: 1, line: 71 },
  "browser_verification.driver": { block_index: 0, line: 32 },
  "code_review.codex.enabled_in_normal": { block_index: 1, line: 75 },
  "code_review.codex.enabled_in_high": { block_index: 0, line: 37 },
  "release_policy.auto_bump": { block_index: 1, line: 77 },
  "release_policy.channel": { block_index: 0, line: 41 },
  "release_policy.trigger_globs": { block_index: 1, line: 78 },
  "merge_policy.strategy": { block_index: 0, line: 46 },
  "merge_policy.auto_merge": { block_index: 1, line: 81 },
};
for (const [path, expected] of Object.entries(expectedProvenance)) {
  assert.deepEqual(result.provenance[path], expected, `provenance mismatch for ${path}`);
}

assert.deepEqual(result.blocks, [
  {
    index: 0,
    language: "yaml",
    fence_start_line: 5,
    content_start_line: 6,
    content_end_line: 49,
    fence_end_line: 50,
  },
  {
    index: 1,
    language: "yml",
    fence_start_line: 54,
    content_start_line: 55,
    content_end_line: 81,
    fence_end_line: 82,
  },
]);
process.stdout.write("ok-merge-provenance\n");
NODE

UNKNOWN_OUT="$TMP/unknown-keys.json"
run_rejected "unknown keys" "$UNKNOWN_OUT" "$TMP/unknown-keys.err" \
  python3 "$SCHEMA" --file "$TMP/unknown-keys.md"
node - "$UNKNOWN_OUT" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
assert.deepEqual(
  result.errors.map(({ code, path, line }) => ({ code, path, line })),
  [
    { code: "unknown_key", path: "knowledge_backends.skillwiki.mystery_option", line: 9 },
    { code: "unknown_key", path: "mystery_mode", line: 5 },
  ],
  "unknown-key diagnostics must be sorted by path",
);
process.stdout.write("ok-unknown-keys\n");
NODE

MALFORMED_OUT="$TMP/malformed.json"
run_rejected "malformed YAML" "$MALFORMED_OUT" "$TMP/malformed.err" \
  python3 "$SCHEMA" --file "$TMP/malformed.md"
node - "$MALFORMED_OUT" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
assert.equal(result.errors.length, 1);
assert.equal(result.errors[0].code, "malformed_yaml");
assert.equal(result.errors[0].line, 5);
process.stdout.write("ok-malformed-yaml\n");
NODE

UNFENCED_OUT="$TMP/unfenced.json"
run_rejected "unfenced YAML" "$UNFENCED_OUT" "$TMP/unfenced.err" \
  python3 "$SCHEMA" --file "$TMP/unfenced.md"
node - "$UNFENCED_OUT" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
assert.deepEqual(
  result.errors.map(({ code, path, line }) => ({ code, path, line })),
  [{ code: "unfenced_yaml", path: "slug", line: 3 }],
);
process.stdout.write("ok-unfenced-yaml\n");
NODE

PROSE_OUT="$TMP/ordinary-prose.json"
python3 "$SCHEMA" --file "$TMP/ordinary-prose.md" >"$PROSE_OUT" ||
  fail "ordinary Markdown prose was rejected"
assert_contract_fields "$PROSE_OUT"
node - "$PROSE_OUT" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
assert.deepEqual(result.config, {});
assert.deepEqual(result.provenance, {});
assert.deepEqual(result.blocks, []);
assert.deepEqual(result.errors, []);
assert.deepEqual(result.warnings, []);
process.stdout.write("ok-ordinary-prose\n");
NODE

UNAVAILABLE_OUT="$TMP/parser-unavailable.json"
run_rejected "parser unavailable" "$UNAVAILABLE_OUT" "$TMP/parser-unavailable.err" \
  python3 -S "$SCHEMA" --file "$TMP/ordinary-prose.md"
node - "$UNAVAILABLE_OUT" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
assert.equal(result.parser.name, "pyyaml");
assert.equal(result.parser.available, false);
assert.equal(result.parser.version, null);
assert.deepEqual(result.config, {});
assert.deepEqual(result.provenance, {});
assert.ok(result.errors.some(({ code }) => code === "parser_unavailable"));
process.stdout.write("ok-parser-unavailable\n");
NODE


cat > "$TMP/live-keys.md" <<'EOF'
```yaml
slug: live-keys
release_branch: main
interview:
  work_item:
    default: native
    upgrade: grill-me
    source: mattpocock/skills
    install: "npx skills add example"
    trigger: auto
    goal_override: never
release_script: bash scripts/release.sh
release_workflow: release.yml
release_policy:
  auto_bump: false
  stable_release_guard: require-main
```
EOF
LIVE_OUT="$TMP/live-keys.json"
python3 "$SCHEMA" --file "$TMP/live-keys.md" >"$LIVE_OUT" ||
  fail "live configuration keys were rejected"
assert_contract_fields "$LIVE_OUT"
node - "$LIVE_OUT" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");
const result = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
assert.deepEqual(result.errors, []);
assert.equal(result.config.interview.work_item.default, "native");
assert.equal(result.config.release_script, "bash scripts/release.sh");
assert.equal(result.config.release_workflow, "release.yml");
assert.equal(result.config.release_policy.stable_release_guard, "require-main");
process.stdout.write("ok-live-config-keys\n");
NODE

printf 'test-dev-loop-config-schema: all checks passed\n'
