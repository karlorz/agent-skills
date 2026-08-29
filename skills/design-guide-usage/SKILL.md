---
name: design-guide-usage
description: Record privacy-safe design-guide usage evidence. Use for design-guide usage status or promotion-review readiness.
---

# Design Guide Usage

Use the bundled recorder for every operation. Do not recreate its validation,
marker, locking, atomic-write, or readiness logic manually.

## Resolve The Recorder

Resolve the directory containing this loaded `SKILL.md`, then use:

```text
<skill-directory>/scripts/design-guide-usage.js
```

Do not derive the path from the current working directory. Do not search
arbitrary repository, home-directory, or plugin-cache descendants. If the
script is missing, report the expected skill-relative path and stop.

## Report Status

Run:

```bash
node "<skill-directory>/scripts/design-guide-usage.js" status --json
```

Let the recorder resolve the active vault through `skillwiki path`. Pass
`--vault <path>` only when the user deliberately supplies an override.

Summarize the counts, missing signals, `eligible`, and `next_action`. Explain
that eligibility only opens a human promotion review and performs no copy,
package, publication, installation, tag, or release action.

## Record Evidence

1. Confirm the observation came from a meaningful frontend task where
   `design-guide` materially influenced the work. Do not count installation,
   recorder implementation, tests, or baseline validation.
2. Gather the explicit evidence fields documented by the recorder's `--help`.
   Use portable project or project-class identities and concise reviewed
   summaries; do not copy private application source.
3. Replace sensitive values with `[REDACTED:<kind>]`. Never persist live
   credentials, tokens, passwords, cookies, bearer headers, private keys,
   customer data, or unrelated private details.
4. Write the reviewed JSON to a bounded temporary file or send it through
   standard input.
5. Run `record --dry-run` and show the proposed entry and readiness delta.
6. Run the write without `--dry-run` only when the user explicitly authorizes
   the write. A request that clearly says to record the reviewed observation
   is authorization; a request to preview, draft, inspect, or discuss it is
   not.
7. Report the evidence identifier, target, updated use count, eligibility, and
   next action. Remove any temporary evidence file containing private context.

Example command shape:

```bash
node "<skill-directory>/scripts/design-guide-usage.js" record \
  --input "<reviewed-json-file>" \
  --dry-run
```

Use the same command without `--dry-run` only after write authority is clear.

## Preserve The Boundary

- Keep recording operator-invoked and attended.
- Never scan Codex, Claude, Cursor, lifecycle-hook, shell-history, transcript,
  or session stores to infer usage.
- Never infer usage because either skill is installed.
- Never append directly to the Markdown log as a fallback after recorder
  failure.
- Never change `PATH`, install a global executable, or copy into a versioned
  plugin cache.
- Never modify or promote `design-guide` as a side effect.
- Fail closed on unresolved vaults, likely secrets, malformed markers,
  duplicates, path escapes, lock contention, or concurrent changes.
