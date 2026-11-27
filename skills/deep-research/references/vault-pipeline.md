# Vault Pipeline Integration

This reference is the single routing home for deep-research vault reads and writes. It implements the HTTP MCP-only frozen-leaf policy from `using-skillwiki` and `skillwiki-mcp`. SKILL.md resolves this route before any vault detection or CLI readiness check.

## Route Resolution (before vault detection or CLI checks)

Feature-detect the live tool list first. Do not run `skillwiki path`, `skillwiki lang`, readiness scripts, or any other local CLI probe before this decision.

1. **Advertised SkillWiki HTTP MCP wins.** When the host advertises wiki tools (`wiki_read_page`, `wiki_query`, `wiki_context`, `wiki_capture`, `wiki_page_publish`, `wiki_workitem_write`, `wiki_log_append`), use them for every vault read and write. Omit `vault` on tool calls to use the handshake's `default_vault`; set `vault` only when the operator explicitly requested an extra vault. This route has no local CLI readiness requirement: do not require `skillwiki path`, `skillwiki lang`, token probes, installs, or a local vault.
2. **No advertised wiki MCP.** Treat the host as a local authoring host only when the resolved vault is writable, is not a mirror or snapshot worktree, and has no `.WIKI_GIT_FROZEN` marker. The local CLI route is available only under the explicit operator opt-in below; without that opt-in, a non-MCP host has no authorized writer and fails closed. Local `skillwiki path` and `doctor` checks may run only as part of that opted-in local route, after the MCP route is ruled out. Never run them to discover a containment boundary.
3. **Neither route authorized.** Use stdout/ephemeral. Do not initialize, install, clone, or git-sync a vault to create a write route.

A **frozen leaf** has `.WIKI_GIT_FROZEN` at the vault root. An **MCP-only leaf** has no writable local authoring vault; its only wiki plane is HTTP MCP. On either leaf, a missing MCP mutation tool is a hard stop, not a reason to write locally.

**Reads** follow the same precedence: advertised MCP read tools (`wiki_query`, `wiki_read_page`, `wiki_context`, `wiki_sources_pending`, ...) first. An existing local mirror is read-only and may lag.

**Language**: on the MCP route, resolve output language from the user or session; do not run `skillwiki lang`. Generate page prose in the resolved language; frontmatter keys, file names, schema headers, citation markers, and wikilink slugs remain English.

## Pre-Orientation Reads (Mandatory Before Writes)

Read through the resolved route:

1. `SCHEMA.md` -- vault structure, taxonomy, conventions
2. `index.md` -- existing pages to cross-link
3. Last 20 entries of `log.md` -- recent vault activity

On the MCP route, use `wiki_read_page` (with `tail_bytes` for an oversized `log.md`) instead of local file reads. If a required read is unavailable, retain the draft and report the gap; do not write blind.

## Related-Pages Search

Before composing the typed page draft, search existing related content through the route:

1. Use `wiki_query` (typed knowledge) or read `index.md`.
2. Check `concepts/`, `queries/`, and related pages.
3. Add wikilinks to discovered pages in the Related Notes section.

## Raw Capture

Raw evidence uses the advertised MCP capture tool. There is no `raw/articles/` ingress in this pipeline.

When `wiki_capture` is advertised, for each source:

1. Call `wiki_capture` with `kind: "note"`, the caller's `project` (use the documented `playground` catch-all when none was given), a short `title`, and `content` containing the source URL, retrieval date, and the exact extracted passages used as evidence.
2. Verify the returned `path` (under `raw/transcripts/`) with `wiki_read_page` in the intended vault.
3. Use that exact returned `raw/transcripts/...` path in the page's `sources:` frontmatter and `^[...]` citation markers. Never invent `raw/articles/...` or any other path.

If the source cannot be represented through `wiki_capture` (for example a binary asset or a capture shape the deployed server rejects), keep the draft outside the vault and report the exact ingestion gap. Do not create a local raw file, do not use a filesystem drop, and do not claim provenance that was not captured. `--no-raw` skips capture and records the provenance gap in the report.

**Binary assets** follow `using-skillwiki/references/save-attachments.md`. HTTP MCP has no binary-upload tool; only an existing enabled clip-outbox ingress on an authoring host can save them. Do not write binaries into the vault directly. On an MCP-only leaf with no supported binary ingress, report the limitation and retain the draft.

## Typed Knowledge Page

Compose typed-knowledge page per `TypedKnowledgeSchema`:

```yaml
---
title: "<Topic Title>"
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: concept  # or comparison, query, entity
tags:
  - research
  - <domain-tag>
sources:
  - "^[raw/transcripts/<date>-note-<slug>.md]"
confidence: medium  # high if 3+ diverse sources, low if single source
provenance: research
---
```

**Page type selection**:

| Research output | Type |
|-----------------|------|
| General topic research | concept |
| Side-by-side comparison | comparison |
| Question-answer focus | query |
| Project/tool summary | entity |

**Citation format**: Use `^[raw/transcripts/<date>-note-<slug>.md]` markers at paragraph end, matching the exact paths returned by `wiki_capture`.

**Body sections**: Follow the synthesis structure defined in SKILL.md Phase 3.

**Diagram placement in page**: If the synthesis includes a Mermaid diagram, place it immediately after the **Overview** section and before the **Findings** section. This gives the wiki reader a visual anchor before diving into source details. If no diagram, omit the section entirely — do not leave a placeholder heading.

## Reusable Research And Follow-Up Queue

When a query page contains a reusable pattern, create a companion
`concepts/<slug>.md` page. The query page answers the specific research
question; the concept page preserves the transferable rule, compatibility
mapping, or implementation pattern for future sessions.

Queue follow-up work only after every typed page publishes successfully.

1. If `wiki_workitem_write` is advertised, create or update the work item under `projects/<slug>/work/<date>-<slug>/spec.md` with CAS: read first via `wiki_read_page`, pass the returned `sha256` as `base_sha256`, and on `FILE_CHANGED` re-read, rebase, and retry once.
2. If `wiki_workitem_write` is absent, use an authorized MCP task capture: `wiki_capture` with `kind: "task"` (or `bug` for a defect) and the proposed work as `content`. This is a non-executing capture, not a work item. Use `idea` or `note` for exploratory findings that should be preserved but not executed.
3. If neither mutation is authorized, retain the draft and report the follow-up gap.

Preserve non-executing proposed intent. Research output must not promote a work item to `in-progress` or add `started`, and must not create `status: planned` work directly; leave lifecycle decisions to the execution workflow.

## Typed-Page Publication (MCP CAS)

`wiki_page_publish` is the publication route whenever it is advertised.

For each query or companion concept:

1. Read the exact target path first with `wiki_read_page`. If it exists, take the returned `sha256` as `base_sha256`. If it does not exist, publish as a create with no `base_sha256`.
2. Compose the complete typed page at an unpublished temporary path outside the vault (the SKILL.md scratch pipeline). Freeze its final frontmatter tags and body bytes.
3. Call `wiki_page_publish` with `path` set to the exact vault-relative target (`queries/<slug>.md` or `concepts/<slug>.md`), `content` set to the frozen bytes, and `base_sha256` for an overwrite. Omit `vault` to use the handshake `default_vault`.
4. On `FILE_CHANGED`, re-read the target, rebase the draft on the current bytes, and retry once. If it changes again, fail closed with the draft retained.
5. On success, require the receipt to report `ok: true`, the intended `vault_id`, and the exact `path`. A mismatched vault or path is not a save: retain the draft and report the mismatch.
6. Read back the exact path with `wiki_read_page`. Compare its returned `sha256` with the SHA-256 of the exact bytes sent. When the response provides `s3_verified`, require `true` and report that proof. If the hash does not match, do not resend; re-read once, report the actual state, and retain the draft if publication is unconfirmed.

Index and log stay managed: never edit `index.md` or `log.md` directly. If a structural log line is required, call `wiki_log_append` with append-only content and verify its `event_path` with `wiki_read_page`.

**Ambiguous mutation.** A timeout, transport drop, or other result that does not prove the server rejected the call is ambiguous. Do not resend the mutation. Reconcile only when the exact target or a returned path is known. For `wiki_page_publish` and `wiki_workitem_write`, the exact target is the path sent: perform exactly one reconcile `wiki_read_page` of that path. If the read matches the intended content hash, record it as published; otherwise treat it as failed, retain the draft, and report the ambiguity as unverified. For `wiki_capture` and `wiki_log_append`, the server assigns `path` / `event_path` only in a successful receipt: if the ambiguous result returned that exact path, reconcile it once; if no path was returned, do not guess a path, do not send a read, stop, keep the draft outside the vault, and report the capture/event as unverified. The same no-resend rule applies to `wiki_capture`, `wiki_workitem_write`, `wiki_log_append`, and `wiki_page_publish`.

If `wiki_page_publish` is not advertised on a frozen or MCP-only leaf, fail closed: keep the draft outside the vault, print the report to stdout, and report the missing mutation tool. Do not run local `skillwiki page publish` as a fallback.

## Local CLI authoring route (explicit operator opt-in)

The local `skillwiki page publish --write` route is allowed only when all of these hold:

- the operator explicitly opts in for this run;
- the host is a verified writable authoring host (not a frozen leaf, not an MCP-only leaf);
- `$VAULT/.WIKI_GIT_FROZEN` is absent;
- the resolved vault and publication target are not a mirror or snapshot worktree and do not resolve through a symlink alias of one.

**Scope of the opt-in.** It authorizes typed-page publication only. It does not
authorize raw capture, binary ingress, or follow-up work-item creation: raw
capture and follow-up work items require the advertised MCP mutations
(`wiki_capture`, `wiki_workitem_write`), and when an MCP mutation is unavailable
the run retains the gap instead of creating a local raw file or work item.
Binary ingress remains limited to an existing enabled clip-outbox ingress (see
Raw Capture). Publication through this route requires existing verified
provenance: every `sources:` entry must already be an exact
`raw/transcripts/...` path whose `wiki_capture` receipt and readback were
verified. If provenance is not already verified, do not publish; keep the draft
outside the vault and report the provenance gap.

The opt-in is per run and must be explicit. A frozen leaf, an MCP-only leaf, or
any MCP error never implies opt-in. After the opt-in, this route may run
`skillwiki path --plain` once to resolve the local vault root and export it as
`DEEP_RESEARCH_VAULT_ROOT` for the containment guard; if it returns
`NO_VAULT_CONFIGURED`, leave the variable unset. That is the only CLI discovery
allowed; the guard itself never calls the CLI.

Then:

1. Run `skillwiki page publish --help`. If unavailable, fail closed.
2. Run the dry run and inspect its operation ID.
3. Repeat the identical command with `--write`.
4. On a nonzero result, retain the draft and operation ID; stop.

Never invoke this route because an MCP call failed, returned an error, timed out, or lacked a tool. MCP errors fail closed. Never write typed pages, `index.md`, or `log.md` directly. Never auto-run `skillwiki init`, install the CLI/plugin, clone, or commit/push to create a route.

## Containment boundary (scratch and `--save`)

The Phase 3 scratch parent and every `--save` target use one boundary inventory
and one guard. The inventory is session-known, never CLI-discovered:

- `DEEP_RESEARCH_VAULT_ROOT` -- the protected vault root when the session already knows it (for example after the explicit local authoring opt-in). Leave it unset when no local path is known.
- `DEEP_RESEARCH_PROTECTED_ROOTS` -- a `PATH`-separator list of additional known vault, mirror, or snapshot-worktree roots.
- `$HOME/wiki` -- conventional local mirror.
- `$HOME/wiki-git` -- conventional snapshot worktree.

Fail closed when the boundary inventory is unresolved: `HOME` is unset and no
explicit root is present, a root is relative, or a root cannot be resolved.
Resolve the target and every root through symlinks (`Path.resolve`), so a target
under a symlink alias of a protected root is blocked. The guard never invokes
`skillwiki`, `git`, or any other CLI; only the explicit operator-opted local
authoring route above may invoke `skillwiki`.

### Canonical containment guard

Set `TARGET` to the absolute path about to be created or written. The guard
prints `outside` (exit 0), `inside` (exit 1), or `error` (exit 2).

```bash
TARGET="/absolute/path/to/write"
if CONTAINMENT_VERDICT="$(python3 - "$TARGET" <<'PY'
# BEGIN deep-research containment guard
import os
import sys
from pathlib import Path

CONVENTIONAL_MIRRORS = ("wiki", "wiki-git")


def _resolve(raw, require_absolute=False):
    if not raw:
        raise ValueError("unresolved path: empty")
    expanded = os.path.expanduser(raw)
    if require_absolute and not os.path.isabs(expanded):
        raise ValueError(f"unresolved root: {raw!r}")
    return Path(expanded).resolve(strict=False)


def _protected_roots(env):
    raw_roots = []
    vault = env.get("DEEP_RESEARCH_VAULT_ROOT", "")
    if vault:
        raw_roots.append(vault)
    raw_roots.extend(
        part
        for part in env.get("DEEP_RESEARCH_PROTECTED_ROOTS", "").split(os.pathsep)
        if part
    )
    home = env.get("HOME", "")
    if home:
        raw_roots.extend(str(Path(home) / name) for name in CONVENTIONAL_MIRRORS)
    if not raw_roots:
        raise ValueError("no protected vault or mirror roots")
    return [_resolve(root, require_absolute=True) for root in raw_roots]


def main(argv):
    if len(argv) != 2:
        print("CONTAINMENT_UNRESOLVED: expected exactly one target path", file=sys.stderr)
        print("error")
        return 2
    try:
        target = _resolve(argv[1])
        roots = _protected_roots(os.environ)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"CONTAINMENT_UNRESOLVED: {exc}", file=sys.stderr)
        print("error")
        return 2
    for root in roots:
        if target == root or root in target.parents:
            print(
                f"CONTAINMENT_BLOCKED: {target} resolves inside protected root {root}",
                file=sys.stderr,
            )
            print("inside")
            return 1
    print("outside")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
# END deep-research containment guard
PY
)"; then
  :
else
  [ "$CONTAINMENT_VERDICT" = "inside" ] || CONTAINMENT_VERDICT="error"
fi
case "$CONTAINMENT_VERDICT" in
  outside) : ;;
  inside) echo "CONTAINMENT_BLOCKED: $TARGET resolves inside a protected root" >&2; exit 1 ;;
  *) echo "CONTAINMENT_UNRESOLVED: protected vault/mirror inventory is unresolved" >&2; exit 1 ;;
esac
```

## `--save` containment guard

Apply the canonical guard with `TARGET` set to the requested `--save` path
before creating parent directories or writing. It resolves the destination
through symlinks and rejects any target inside the vault root, `$HOME/wiki`,
`$HOME/wiki-git`, an explicit `DEEP_RESEARCH_PROTECTED_ROOTS` entry, or a symlink
alias of one. Only after an `outside` verdict, create the parent directory and
write. A blocked or unresolved target is not a save: print the report to stdout
and report the rejected target. Never call `skillwiki path` or any other CLI to
discover the boundary.

## Safety Rules

1. Advertised SkillWiki MCP wins for every vault read and write; the MCP route has no local CLI readiness requirement.
2. A frozen or MCP-only leaf that lacks a required MCP mutation fails closed with the draft outside the vault. No local fallback, auto `skillwiki init`, install, or git.
3. Never write typed pages, `index.md`, or `log.md` directly. Never use local `skillwiki page publish` as a fallback from an MCP error.
4. An ambiguous mutation is not retried. Reconcile once when the exact path is known; retain the draft and report unverified when the path or saved content is unconfirmed.
5. Check every successful write receipt's `vault_id` and exact `path`; verify the published bytes with `wiki_read_page` hash comparison and `s3_verified` when provided.
6. Apply the canonical containment guard to the scratch parent and every `--save` target before creating directories or writing. It uses session-known roots plus `$HOME/wiki` and `$HOME/wiki-git`, resolves symlinks, never invokes the CLI, and fails closed when the boundary inventory is unresolved.
7. The local CLI opt-in covers typed-page publication with already-verified provenance only; raw capture and follow-up work items remain MCP-required or retained as gaps.
8. Respect `--no-raw` for quick lookups; record the resulting provenance gap.
9. Source failures keep other sources; note them in the report.
10. Log all vault route and receipt decisions in the research report.

## Worked Example: Coverage-Sweep Pattern

Deep-research can complement an automated collector (e.g., a nightly GitHub
Search pipeline) by finding sources the collector structurally misses:
blog-first announcements, org-launched repos with short names, non-English
ecosystems, and industry news. The pattern:

### When to use

- An automated collector has returned zero candidates for multiple consecutive
  runs (dedupe saturation or query-portfolio exhaustion).
- A major release is announced on X/Twitter, HN, or a company blog and the
  collector's keyword queries would not match it.
- A quarterly or weekly attended review of the research landscape.

### Prompt template

```
Research the current <domain> landscape for <time period>, focusing on
sources the nightly GitHub-Search-only collector missed. This is a vault-aware
research run - the vault is at <vault path>.

## Research Topics

1. <specific repo/announcement> - Research <URL>: What is it? Architecture,
   purpose, tech stack. Relevance to <your system>.
2. Major <domain> releases <time period> - Search for:
   - "<org> open source agent 2026"
   - "<domain> framework release <month> 2026"
   - Any major releases from <org list> in the <domain> space
3. Coverage gap analysis - The current collector uses these queries:
   <list of queries>. What types of repos or announcements would these
   queries MISS?

## Output

Save the research as a vault query page. Include a "Recommendations for
Collector Query Portfolio" section with specific new queries or org-watchlist
entries that would close the coverage gap.
```

### Expected artifacts

A single deep-research run produces:

| Artifact | Path | Purpose |
|----------|------|---------|
| Raw evidence | `raw/transcripts/<date>-note-<slug>.md` | `wiki_capture` receipt; the exact returned path is the source |
| Query page | `queries/<date>-<slug>.md` | Full research report with TL;DR, findings, freshness table |
| Concept page (optional) | `concepts/<slug>.md` | Reusable pattern or taxonomy distilled from the research |
| Work item (optional) | `projects/<project>/work/<date>-<slug>/spec.md` | `wiki_workitem_write` CAS with `status: proposed`, or an MCP task capture |

### Post-run validation checklist

1. `wiki_read_page` on every published page returns the intended `sha256`; when the response includes `s3_verified`, it is `true`.
2. Every `sources:` entry is an exact `raw/transcripts/...` path returned by `wiki_capture`.
3. If a work item was created, it remains `status: proposed` (non-executing) and its `kind` matches the vault's SCHEMA.md.
4. Every successful write receipt reports the intended `vault_id` and exact `path`.
5. No local git commit is part of this pipeline; an authoring host's own sync owns commits.
