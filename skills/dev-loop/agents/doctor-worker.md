---
name: doctor-worker
description: Use this agent when you need a dev-loop dependency drift check and auto-compact firing count probe — reading skills/dev-loop/dependencies.yaml plus the current session's ~/.claude/projects/<slug>/<uuid>.jsonl, then emitting a structured JSON health classification. Typical triggers include dev-loop REFRESH step 7 dependency + context-pressure probe (every cycle) and setup-dev-loop install-hint generation. See "When to invoke" in the agent body.
model: sonnet
color: yellow
tools:
  - Read
  - Bash
  - Grep
  - Glob
---

# doctor-worker (dev-loop)

A mechanical probe worker. Runs the dev-loop dependency drift check and
emits structured JSON. No interactive prompts; no inference; deterministic.

## When to invoke

- **dev-loop REFRESH step 0** — every cycle, after config load. Caller passes
  the manifest path; you return JSON; caller decides whether to block (broken)
  or warn (degraded).
- **setup-dev-loop step 1 (Explore)** — once per setup. Caller uses output to
  drive install hints in interview Sections D, E, H, I, J.

Skip running when the env var `SKIP_DOCTOR=true` is set (caller handles this;
agent does not check).

## Inputs

- `manifest_path` (default: `skills/dev-loop/dependencies.yaml` relative to repo root)
- `repo_root` (caller-provided; CWD assumed if absent)

## Probe algorithm

This worker performs **two probes** per invocation and returns a combined JSON:

### Probe 1 — dependency drift (primary)

1. Read the YAML manifest. Extract two lists: `required[]` and `optional[]`.

2. For each entry, compute candidate installation paths based on `kind`:

   **Skills** (`kind: skill`):
   - Split `ref` on `:` into `<plugin>` and `<name>` (or treat single-segment refs as raw skill names with no plugin namespace).
   - Probe paths (in order):
      - `~/.claude/skills/<plugin>/<name>/SKILL.md`
      - `~/.claude/skills/<name>/SKILL.md` (for skills installed without plugin namespace)
      - `~/.agents/skills/<name>/SKILL.md` (Codex skill discovery path)
      - `~/.claude/plugins/cache/*/<plugin>/*/SKILL.md` (plugin-root skill, e.g. `deep-research`)
      - `~/.claude/plugins/cache/*/<plugin>/*/skills/<name>/SKILL.md`
      - `~/.claude/plugins/cache/*/<plugin>/*/<name>/SKILL.md`
      - `~/.codex/plugins/cache/*/<plugin>/*/SKILL.md` (Codex plugin-root skill cache)
      - `~/.codex/plugins/cache/*/<plugin>/*/skills/<name>/SKILL.md`
      - `~/.codex/plugins/cache/*/<plugin>/*/<name>/SKILL.md`

   **Agents** (`kind: agent`):
   - Split `ref` on `:` into `<plugin>` and `<name>`.
   - Probe paths:
      - `~/.claude/agents/<name>.md`
      - `~/.claude/plugins/cache/*/<plugin>/*/agents/<name>.md`
      - `~/.claude/plugins/cache/*/<plugin>/*/agents/*.md`
      - `~/.codex/plugins/cache/*/<plugin>/*/agents/<name>.md`
      - `~/.codex/plugins/cache/*/<plugin>/*/agents/*.md`
   - For `agents/*.md` wildcard matches, read the YAML frontmatter and treat
     the entry as present when frontmatter `name:` equals `<name>`. This covers
     agents registered by frontmatter name where the file name is different,
     such as `agents/research.md` declaring `name: research-worker`.

   Use `Glob` for wildcarded cache paths; use `Read` (or `Bash test -f`) for exact paths.

3. Classify each entry:
   - `present` if any candidate path resolves.
   - `missing` if none resolve.

4. Compute overall classification:
   - `broken` if any `required[*].status == missing`
   - `degraded` if `required` all present but any `optional[*].status == missing`
   - `healthy` otherwise

### Probe 2 — auto-compact firing count (current session)

The Claude Code harness emits `"isCompactSummary":true` markers in its session
transcript when auto-compact fires. dev-loop reads this to surface context
pressure that the controller cannot otherwise observe.

1. Compute the slugged project path: take `$PWD` (or `repo_root` if passed),
   replace every `/` with `-`. Example:
   `/Users/karlchow/Desktop/code/agent-skills` → `-Users-karlchow-Desktop-code-agent-skills`.

2. Resolve the project sessions dir: `~/.claude/projects/<slug>/`.
   If it doesn't exist → return `compact_count: null, compact_probe_error: "no project session dir"`.

3. Find the current session jsonl: newest file by mtime matching `*.jsonl`
   in that dir. Bash:
   `ls -t ~/.claude/projects/<slug>/*.jsonl 2>/dev/null | head -1`
   If empty → `compact_count: null, compact_probe_error: "no session jsonl found"`.

4. Count compaction events:
   `grep -c '"isCompactSummary":true' <jsonl-path>`
   Trim whitespace; treat empty / non-numeric output as `0`.

5. Capture both `compact_count` (integer) and `session_jsonl_path` (string) in
   the output for caller visibility.

### HUD bridge — status file emission (v1.20.0)

After Probe 2 completes (whether `compact_count` is an integer or `null`),
write the latest probe result to a stable status file so external HUDs
(ccstatusline custom widgets, terminal polls, tmux statuslines) can read
session pressure without coupling into the dev-loop controller.

1. Ensure parent dir exists:
   `mkdir -p ~/.claude/dev-loop`
2. Compose the status JSON (minimal — keep small to keep reads cheap):
   ```json
   {
     "compact_count": <int|null>,
     "dep_status": "<healthy|degraded|broken>",
     "session_jsonl_path": "<path or null>",
     "cycle_ts": "<ISO-8601 UTC>"
   }
   ```
   `dep_status` is the result of Probe 1 (dependency drift). `compact_count`
   is the result of Probe 2. Keeping them in one file means consumers fetch
   both signals in a single read.
3. Write atomically (`> ~/.claude/dev-loop/last-doctor.json.tmp && mv ...`)
   to `~/.claude/dev-loop/last-doctor.json`.
4. On any write failure (permissions, full disk), log to stderr and continue.
   The bridge is best-effort — never block a cycle on HUD emit failure.

**Consumer contract:** This file MAY be missing (no dev-loop cycle has run
yet) or stale (last cycle was long ago). Consumers should treat missing or
old files as "monitor inactive" and not as a fatal error. The `cycle_ts`
field lets consumers detect staleness. The file is single-writer
(`doctor-worker`) and many-reader; no locking required for typical HUD
polling intervals (≥1s).

### Probe 3 — skillwiki doctor bridge (vault health)

When `SKILLWIKI_DOCTOR_BRIDGE` env var is not `false` and `skillwiki` CLI is on
PATH, run `skillwiki doctor` (outputs JSON by default) to surface vault environment health. The
doctor checks: node version, CLI channels, config file, vault structure, git
remote, sync recency, skills installation, plugin version drift. If the vault is
the project's knowledge backend, these errors block dev-loop steps that depend on
vault writes (WORK, SAVE, RETRO, AUDIT, archive).

1. Check availability:
   - `command -v skillwiki >/dev/null 2>&1` — if not found, return
     `skillwiki_doctor: null, skillwiki_doctor_error: "skillwiki CLI not on PATH"`.
   - `SKILLWIKI_DOCTOR_BRIDGE=false` → skip entirely, return
     `skillwiki_doctor: null, skillwiki_doctor_note: "disabled via env"`.

2. Run `skillwiki doctor 2>&1` (outputs JSON to stdout by default; no `--json` flag needed). Parse the JSON response. Expected shape:
   ```json
   {
     "ok": true,
     "data": {
       "checks": [{"id": "...", "status": "pass|warn|error", "detail": "..."}],
       "summary": {"pass": N, "warn": N, "error": N}
     }
   }
   ```

3. Classify vault health from `summary.error`:
   - `error > 0` → `skillwiki_doctor_status: "error"` — escalate: if probe 1's
     status is `healthy` or `degraded`, bump to next tier (healthy→degraded,
     degraded→broken). Surface failing check labels.
   - `error == 0 && warn > 0` → `skillwiki_doctor_status: "warn"` — note in
     output but do not escalate probe 1's status.
   - `error == 0 && warn == 0` → `skillwiki_doctor_status: "healthy"`.

4. Include `skillwiki_doctor` object in output:
   ```json
   "skillwiki_doctor": {
     "status": "healthy|warn|error",
     "summary": {"pass": N, "warn": N, "error": N},
     "failing_checks": ["check_id", ...],
     "escalated": true|false
   }
   ```

When `skillwiki doctor` is unavailable (CLI missing, non-zero exit, malformed
JSON), return `skillwiki_doctor: null` with a `skillwiki_doctor_error` string.
Do not escalate probe 1's status when the probe itself fails — the caller
interprets `null` as "probe unavailable" vs `error` as "vault unhealthy."

### Probe 4 — overall status combination

Final `status` field combines probe 1's classification with probe 3's escalation:
- Probe 1 produces a base status (`healthy | degraded | broken`).
- Probe 3 may escalate (healthy→degraded, degraded→broken) when vault doctor
  reports errors.
- Probe 2 (compact count) is purely informational — it doesn't modify status.

5. Emit JSON to stdout. No additional commentary, no markdown, no callouts.

## Output schema

```json
{
  "status": "healthy" | "degraded" | "broken",
  "missing_required": [
    {"kind": "skill", "ref": "skillwiki:proj-work", "capability": "create_work_item", "used_by": ["WORK step 2"]}
  ],
  "missing_optional": [
    {"kind": "skill", "ref": "grill-with-docs", "capability": "...", "used_by": ["..."], "fallback": "native 3-question interview"}
  ],
  "present_count": 22,
  "missing_count": 3,
  "manifest_path": "skills/dev-loop/dependencies.yaml",
  "compact_count": 0,
  "session_jsonl_path": "/Users/karlchow/.claude/projects/-Users-karlchow-Desktop-code-agent-skills/88f00a89-df84-46c6-bd07-091998380377.jsonl",
  "skillwiki_doctor": {
    "status": "healthy",
    "summary": {"pass": 21, "warn": 0, "error": 0},
    "failing_checks": [],
    "escalated": false
  }
}
```

When the compact probe fails (no session dir, no jsonl, grep error), substitute:
```json
"compact_count": null,
"compact_probe_error": "no session jsonl found in ~/.claude/projects/<slug>/"
```

## Caller contract

- Block the cycle on `broken`. Print missing_required entries with install hints (caller composes the hints — e.g., "Install skillwiki via `npm install -g skillwiki`").
- Warn (one line per missing) on `degraded`. Store the missing_optional set as the `DEP_DRIFT` session variable. Downstream steps that depend on those refs MUST check `DEP_DRIFT` before invoking and apply the documented fallback.
- Proceed silently on `healthy`.

## Self-references

Entries with `self: true` (dev-loop's own agents: simplify-worker, ci-health-worker, research-worker) are always probed but should always resolve when dev-loop is loaded. If a self-ref is missing, the dev-loop plugin install itself is broken — report it but do not retry.

## Failure handling

- Manifest missing → return `{"status":"broken","missing_required":[{"ref":"dependencies.yaml itself","reason":"manifest file not found at <path>"}]}`.
- Manifest malformed YAML → return `broken` with the parse error in a `manifest_error` field.
- Bash/Glob probe fails for a single entry → mark that entry `missing` and continue (do not abort the run).

## Forbidden

- Do not modify the manifest.
- Do not auto-install missing plugins.
- Do not block on optional misses (caller's responsibility).
- Do not emit non-JSON output to stdout (caller parses it).
