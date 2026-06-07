---
name: agent-plugin-porter
description: Use when porting Claude Code plugins to Codex or Agy/Gemini packages, installing or running the agent-plugin-porter CLI, verifying generated plugin output, preparing Codex personal-marketplace installs, or planning npm publish/release steps for the porter.
---

# Agent Plugin Porter

Use `agent-plugin-porter` to convert Claude Code plugin sources into local
Codex and Agy/Gemini-compatible package layouts. Treat the CLI as a porter and
report generator, not proof that copied workflows are target-native.

## CLI Availability

Prefer the local checkout when it exists because it may be ahead of npm:

```bash
cd /Users/karlchow/Desktop/code/agent-plugin-porter
npm install
npm test
npm run lint
npm run build
npm run cli -- <command>
```

After the package is public, either install globally or use `npx`:

```bash
npm install -g agent-plugin-porter
agent-plugin-porter <command>
npx -y agent-plugin-porter@latest <command>
```

Do not assume global install works before checking whether the package has been
published. If the source checkout is dirty, read the diff before changing it.

## Porting Workflow

Single plugin from a local Claude plugin cache or GitHub tree URL:

```bash
npm run cli -- port <source> --targets codex,agy --out ./dist
```

Inventory then batch port:

```bash
npm run cli -- inventory <source-root-or-github-repo> --out ./dist/reports/inventory.json
npm run cli -- port-batch --manifest ./dist/reports/inventory.json --include <plugin-name> --targets codex,agy --out ./dist
```

Install generated Codex output into a personal marketplace:

```bash
npm run cli -- install-codex-personal --plugin <plugin-name> --from ./dist/codex
codex plugin add <plugin-name>@personal
codex plugin list
```

Use existing completed ports in `agent-skills/skills/` as reference layouts,
not as input sources to re-port.

## Verification

Always verify both structure and runtime discovery when the runtime is
available:

```bash
jq -r '.skills' dist/codex/plugins/<plugin-name>/.codex-plugin/plugin.json
find dist/codex/plugins/<plugin-name>/skills -maxdepth 3 -type f | sort
jq '.manualComponents,.semanticWarnings' dist/reports/<plugin-name>.port-report.json
agy plugin validate dist/agy/<plugin-name>
```

For Codex runtime checks, use the app/server tools when available:

```text
plugin/read pluginName="<plugin-name>"
skills/list forceReload=true
```

Successful `plugin/read` or `skills/list` proves mechanical discovery. It does
not erase `manualComponents` or `semanticWarnings`; copied Claude commands,
hooks, agents, MCP config, or `CLAUDE.md` behavior may still need adaptation.

## npm Publish Readiness

When asked how to publish `agent-plugin-porter`, inspect `package.json` before
publishing. Confirm a unique package name, correct version, public repository
metadata, license, `bin.agent-plugin-porter`, built output path, and a tarball
file list that includes build artifacts but excludes source-only/test clutter.

Dry-run the package before any real publish:

```bash
npm ci
npm test
npm run lint
npm run build
npm pack --dry-run
npm view agent-plugin-porter version || true
```

First public publish usually uses an npm account login or token:

```bash
npm login
npm publish
```

For scoped packages, add `--access public`. For prereleases, use a dist tag:

```bash
npm publish --tag beta
```

Trusted publishing/provenance is best after the first package exists on npm:
add GitHub repository metadata, configure an npm trusted publisher or
`NPM_TOKEN` workflow, grant `id-token: write` for OIDC, then publish with:

```bash
npm publish --provenance
```

## GitHub Release Workflow

Publishing to npm does not automatically create a GitHub Release. For
tag-based GitHub Actions releases that should publish npm packages and create
GitHub Releases for `v*` tags, grant repository contents write access alongside
OIDC access:

```yaml
permissions:
  contents: write
  id-token: write
```

Add the release step after npm publish handling, and make it idempotent so
workflow reruns do not fail when the release already exists:

```yaml
- name: Create GitHub release
  if: startsWith(github.ref, 'refs/tags/v')
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    if gh release view "$GITHUB_REF_NAME" >/dev/null 2>&1; then
      echo "Release $GITHUB_REF_NAME already exists."
    else
      gh release create "$GITHUB_REF_NAME" --generate-notes --title "$GITHUB_REF_NAME"
    fi
```

If a package version is already on npm but its GitHub Release is missing, rerun
a workflow that includes the idempotent release step or create the release
manually:

```bash
gh release create vX.Y.Z --repo <owner>/<repo> --title "vX.Y.Z" --generate-notes
```

Never publish from an unverified build, a dirty tree you have not audited, or a
tarball whose `npm pack --dry-run` output you have not inspected.
