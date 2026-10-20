# Isolated diagnostics

Run config rendering, skill-discovery comparisons, and compaction experiments
inside a disposable home. A completed filesystem write persists after a
conversation rewind.

## Isolation boundaries

- Set `GROK_HOME` to a private directory and set both `HOME` and Windows
  `USERPROFILE` to a private user directory. Pass the same user directory as
  `install.sh --user-home` so cross-harness rule files stay inside the fixture.
- Clear inherited `GROK_CONFIG` and `GROK_CONFIG_PATH`. Both are allowlisted
  overlays; skill-discovery experiments require a complete isolated config.
- Run from the scratch directory so project-level configuration stays scoped.
  Set `GROK_DISABLE_AUTOUPDATER=1` and use `--skip-plugins --skip-grokgod` for
  installer fixtures. Add `--no-config` when testing file installation alone.
- Copy only the required plugin registry and definitions. Use independent
  copies for writable files. For model/compaction probes, remove connector and
  hook declarations from disposable copies and verify zero unintended MCP
  servers before sending a prompt.
- Hash the live config before and after. A mismatch fails the diagnostic:
  stop, inspect the diff, and preserve any concurrent user edits before an
  attended restoration. Backups provide recovery evidence.
- Remove only scratch created by the diagnostic. Keep raw config and inspect
  output private; they may contain credentials or host paths.

## Unix / Git Bash fixture

Resolve absolute paths to `INSTALL`, `PY`, and the desired Grok binary before
changing homes. The interpreter needs Python 3.11+ `tomllib`, or `tomli`.

```bash
INSTALL=/absolute/path/to/scripts/install.sh
PY="$(command -v python3)"
LIVE="$HOME/.grok/config.toml"
hash_config() {
  "$PY" -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$LIVE"
}
before="$(hash_config)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/grok-diag.XXXXXX")"
mkdir -p "$scratch/user" "$scratch/grok" "$scratch/bin"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$PY" > "$scratch/bin/python3"
chmod +x "$scratch/bin/python3"
(
  cd "$scratch" || exit 1
  unset GROK_CONFIG GROK_CONFIG_PATH
  export HOME="$scratch/user" USERPROFILE="$scratch/user"
  export GROK_HOME="$scratch/grok" GROK_DISABLE_AUTOUPDATER=1
  PATH="$scratch/bin:$PATH" bash "$INSTALL" \
    --grok-home "$GROK_HOME" --user-home "$HOME" \
    --no-config --skip-plugins --skip-grokgod -y
)
result=$?
after="$(hash_config)"
[ "$before" = "$after" ] || { echo 'FAILED: live config changed'; result=1; }
rm -rf "$scratch"
[ "$result" -eq 0 ]
```

For Windows Git Bash, set `PY` to the installed interpreter, for example
`/c/Program Files/Python312/python.exe`. The fixture's `python3` wrapper makes
all installer subprocesses use that interpreter. Native PowerShell helpers
can invoke `& 'C:\Program Files\Python312\python.exe'` directly.

For discovery or compaction testing, prepare the required independent config
and plugin copies inside the fixture, run the selected CLI with the same
isolation variables, and retain the before/after live hash check. Compare
`grok inspect --json` discovery rows separately from the Available Skills
blocks saved in session chat history. Prompt evidence establishes which
skills were shown to the model.

## Installer write scope

`--grok-home` owns agents, routing rules, `AGENTS.md`, config, backups, and the
installation stamp. `--user-home` owns cross-harness English-rule paths.
Plugin operations require `--skip-plugins` during isolated diagnostics.
The harness tests hash an unrelated config sentinel around a fixture install.
