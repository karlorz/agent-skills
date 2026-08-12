#!/usr/bin/env bash
#
# test-smoke-ephemeral.sh — focused self-test for the smoke-ephemeral.sh report
# extraction, WITHOUT invoking grok.
#
# Exercises the real production path end-to-end: a stub `grok` executable (in a
# temporary PATH) feeds a canned full stream to smoke-ephemeral.sh, and the test
# asserts what lands in cell.md / cell.full.md / meta.json. Covers:
#
#   1. marker on its own line
#   2. marker inline after narration (the live q2-D failure: the model appended
#      "===REPORT===" inline; the line-anchored awk then copied the whole stream,
#      so cell.md == cell.full.md, narration plus two reports)
#   3. two markers — suffix after the last
#   4. no marker — full stream fallback
#   5. empty suffix — full stream fallback
#   6. (brief requirement 6) cell.md contains the final report only for the
#      inline example; meta.json still records exit code / outcome / byte counts
#   7. (task 1) no output-dir arg -> exactly one run directory under
#      $DEEP_RESEARCH_DEV_ARTIFACT_ROOT, with an extracted cell.md
#   8. (task 1) output-dir inside the resolved vault -> exit 2, guard message,
#      no cell.full.md, and no stub-Grok invocation
#   9. (reviewer fix) vault root from a stub `skillwiki` emitting pretty/
#      multiline JSON -> still rejected with exit 2, no output dir created,
#      and no stub-Grok invocation
#  10. (task 10a r4) stub `skillwiki` failing both `path` and `path --plain`
#      -> must fail closed: exit 3, vault-resolution/boundary diagnostic, no
#      output dir, no stub-Grok invocation (RED on the current guard, which
#      skips when resolution fails)
#  11. (task 10a r5) containment-probe failure (stub python3 exits 42 for
#      `python3 - <candidate> <parent>`) -> must fail closed: exit 3,
#      boundary/probe diagnostic, no output dir, no stub-Grok invocation
#      (RED on the current guard, which skips when the probe fails).
#      $TMP/vault-r5 is created before the run so the stub's bare resolver
#      output passes strict root validation and the run reaches the probe
#      stage (probe failure, not resolver-stage fallback)
#  12. (task 10c r6) containment-probe failure with the ORDINARY Python
#      exception exit code 1 (stub python3 exits 1 for
#      `python3 - <candidate> <parent>`) -> must fail closed: exit 3,
#      boundary/probe diagnostic, no output dir, no stub-Grok invocation
#      (RED on the current guard, which reads exit 1 as the normal
#      outside-vault verdict)
#  13. (task 10c r7) unrecognized nonempty `skillwiki` output
#      (`skillwiki unrecognized output`, exit 0 for `path --plain`/`path`)
#      -> must fail closed: exit 3, vault-resolution/boundary diagnostic,
#      no output dir, no stub-Grok invocation (RED on the current resolver,
#      which accepts arbitrary nonempty non-JSON output as a vault root)
#  14. (task 10d r8) explicit RELATIVE vault override
#      (DEEP_RESEARCH_DEV_VAULT_ROOT=relative-vault) -> must fail closed:
#      exit 3, vault-resolution/boundary diagnostic, no output dir, no
#      stub-Grok invocation (RED on the current resolver, which returns the
#      override verbatim, unvalidated)
#  15. (task 10d r9) explicit nonexistent ABSOLUTE vault override
#      (DEEP_RESEARCH_DEV_VAULT_ROOT=$TMP/nonexistent-override-vault, never
#      created) -> must fail closed: exit 3, vault-resolution/boundary
#      diagnostic, no output dir, no stub-Grok invocation (RED on the current
#      resolver, which returns the override verbatim, unvalidated)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE="$SCRIPT_DIR/smoke-ephemeral.sh"
HELPER="$SCRIPT_DIR/extract-report.py"

PASS=0
FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-smoke-ephemeral.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS + 1)); printf 'ok:   %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$*"; }

# check <label> <expected-file> <actual-file>
check() {
  if cmp -s "$2" "$3"; then
    ok "$1"
  else
    bad "$1"
    diff -u "$2" "$3" || true
  fi
}

# ---- section 0: syntax gate -------------------------------------------------
if bash -n "$SMOKE"; then
  ok "syntax: bash -n smoke-ephemeral.sh"
else
  bad "syntax: bash -n smoke-ephemeral.sh"
fi

# ---- fixtures ---------------------------------------------------------------
# (a) marker on its own line, blank + whitespace-only lines after it
cat > "$TMP/a.full" <<'EOF'
narration line one
narration line two
===REPORT===

   
**Status: Full** final report body, marker was on its own line
EOF
cat > "$TMP/a.expected" <<'EOF'
**Status: Full** final report body, marker was on its own line
EOF

# (b) marker inline after narration (live q2-D pattern)
cat > "$TMP/b.full" <<'EOF'
The research agent finished. Spot-checking its core claims against the primary sources before reporting.
- All planned questions returned usable structured research; no claims were dropped and no source-plan channel failed.===REPORT===

**Status: Partial** — local-only analysis: the checked-out tree is the primary source and external freshness was intentionally skipped.

# Deep Research: Grok Build's built-in /deep-research workflow

## TL;DR

- `/deep-research` is a built-in Rhai workflow compiled into the shell binary.
EOF
cat > "$TMP/b.expected" <<'EOF'
**Status: Partial** — local-only analysis: the checked-out tree is the primary source and external freshness was intentionally skipped.

# Deep Research: Grok Build's built-in /deep-research workflow

## TL;DR

- `/deep-research` is a built-in Rhai workflow compiled into the shell binary.
EOF

# (c) two markers — first on its own line, second inline; take suffix after last
cat > "$TMP/c.full" <<'EOF'
narration before the first marker
===REPORT===

Draft A — first pass, not the final word
The synthesizer then finalized the report.===REPORT===

**Status: Final** only this section survives
EOF
cat > "$TMP/c.expected" <<'EOF'
**Status: Final** only this section survives
EOF

# (d) no marker -> full stream fallback
cat > "$TMP/d.full" <<'EOF'
just narration
no report marker anywhere in this stream
EOF
cp "$TMP/d.full" "$TMP/d.expected"

# (e) marker with empty suffix -> full stream fallback
cat > "$TMP/e.full" <<'EOF'
narration line
===REPORT===
EOF
cp "$TMP/e.full" "$TMP/e.expected"

# ---- stub grok (never invokes the real CLI) ---------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/grok" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${GROK_STUB_CALLED:-}" ]]; then
  touch "$GROK_STUB_CALLED"
fi
cat "$GROK_STUB_OUTPUT"
exit "${GROK_STUB_EXIT:-0}"
EOF
chmod +x "$TMP/bin/grok"

# run_cell <name> <fixture> <expected-cell> — one full harness run via stub
run_cell() {
  local name="$1"
  local fixture="$2"
  local expected="$3"
  local rundir="$TMP/run-$name"
  local log="$TMP/run-$name.log"
  local rc
  GROK_STUB_OUTPUT="$fixture" GROK_STUB_EXIT=0 \
    PATH="$TMP/bin:$PATH" bash "$SMOKE" "test query $name" "$rundir" \
    >"$log" 2>&1
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    bad "$name: smoke-ephemeral.sh exited $rc (see $log)"
    return 1
  fi
  check "$name: cell.md is final report only" "$expected" "$rundir/cell.md"
  check "$name: cell.full.md is the full stream" "$fixture" "$rundir/cell.full.md"
}

# ---- section 1: end-to-end through the real harness (stub grok) -------------
run_cell a "$TMP/a.full" "$TMP/a.expected" || true
run_cell b "$TMP/b.full" "$TMP/b.expected" || true
if ! grep -Fq 'no claims were dropped' "$TMP/run-b/cell.md"; then
  ok "b: narration absent from cell.md"
else
  bad "b: narration leaked into cell.md"
fi
if ! grep -Fq '===REPORT===' "$TMP/run-b/cell.md"; then
  ok "b: marker absent from cell.md"
else
  bad "b: marker leaked into cell.md"
fi
run_cell c "$TMP/c.full" "$TMP/c.expected" || true
if ! grep -Fq 'Draft A' "$TMP/run-c/cell.md"; then
  ok "c: pre-final draft absent from cell.md"
else
  bad "c: pre-final draft leaked into cell.md"
fi
run_cell d "$TMP/d.full" "$TMP/d.expected" || true
run_cell e "$TMP/e.full" "$TMP/e.expected" || true

# ---- section 2: meta.json contract (harness behavior preserved) -------------
# check_meta <label> <meta.json> <exp_exit> <exp_outcome>
check_meta() {
  local label="$1" meta="$2" exp_exit="$3" exp_outcome="$4"
  if python3 - "$meta" "$exp_exit" "$exp_outcome" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
exp_exit = int(sys.argv[2])
exp_outcome = sys.argv[3]
assert meta["exit_code"] == exp_exit, (meta["exit_code"], exp_exit)
assert meta["outcome"] == exp_outcome, (meta["outcome"], exp_outcome)
assert meta["phase"] == "smoke" and meta["cell"] == "cell.md"
for key in ("run_id", "lane", "query_id", "attempt", "model", "slash",
            "cwd", "started", "finished", "duration_s", "bytes_stdout",
            "bytes_report", "purpose"):
    assert key in meta, key
if exp_exit == 0:
    # requirement 6: for the inline example, cell.md must be strictly smaller
    # than the full stream (old bug: cell.md == cell.full.md, 36,355 bytes)
    assert meta["bytes_report"] < meta["bytes_stdout"], (
        "cell.md must not equal the full stream")
print("exit_code=%s outcome=%s bytes_stdout=%s bytes_report=%s"
      % (meta["exit_code"], meta["outcome"],
         meta["bytes_stdout"], meta["bytes_report"]))
PY
  then
    ok "$label"
  else
    bad "$label"
  fi
}

check_meta "b: meta.json valid — exit 0, outcome ok, bytes_report < bytes_stdout" \
  "$TMP/run-b/meta.json" 0 ok

# failed grok run: exit handling must be preserved, extraction must still work
mkdir -p "$TMP/run-fail"
GROK_STUB_OUTPUT="$TMP/b.full" GROK_STUB_EXIT=3 \
  PATH="$TMP/bin:$PATH" bash "$SMOKE" "test query fail" "$TMP/run-fail" \
  >"$TMP/run-fail.log" 2>&1 || true
check_meta "fail: meta.json valid — exit 3, outcome failed" \
  "$TMP/run-fail/meta.json" 3 failed
check "fail: cell.md still extracted on failed run" \
  "$TMP/b.expected" "$TMP/run-fail/cell.md"

# ---- section 3: helper unit checks (byte-exact) -----------------------------
if [[ -f "$HELPER" ]]; then
  # e2: marker followed by whitespace only -> full stream fallback
  printf 'narration\n===REPORT===   \n' > "$TMP/e2.full"
  if python3 "$HELPER" "$TMP/e2.full" > "$TMP/e2.cell"; then
    check "e2: whitespace-only suffix falls back to full stream" \
      "$TMP/e2.full" "$TMP/e2.cell"
  else
    bad "e2: helper failed"
  fi

  # e3: two markers on one line -> suffix after the last
  printf '===REPORT===draft===REPORT===final only\n' > "$TMP/e3.full"
  printf 'final only\n' > "$TMP/e3.expected"
  if python3 "$HELPER" "$TMP/e3.full" > "$TMP/e3.cell"; then
    check "e3: two markers on one line, suffix after last" \
      "$TMP/e3.expected" "$TMP/e3.cell"
  else
    bad "e3: helper failed"
  fi
else
  bad "helper missing: $HELPER (part of the fix under test)"
fi

# ---- section 4: artifact routing (task 1) -----------------------------------
# r1: default artifact root — no output-dir argument -> exactly one run
#     directory under $DEEP_RESEARCH_DEV_ARTIFACT_ROOT with an extracted
#     cell.md (env -u: keep the run immune to an ambient vault override)
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-default" \
  PATH="$TMP/bin:$PATH" DEEP_RESEARCH_DEV_ARTIFACT_ROOT="$TMP/default-artifacts" \
  env -u DEEP_RESEARCH_DEV_VAULT_ROOT bash "$SMOKE" "test query default-root" \
  >"$TMP/run-default.log" 2>&1 || bad "r1: smoke-ephemeral.sh exited $? (see $TMP/run-default.log)"

r1_count="$(find "$TMP/default-artifacts" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || true)"
if [[ "$r1_count" -eq 1 ]]; then
  ok "r1: exactly one run directory under DEEP_RESEARCH_DEV_ARTIFACT_ROOT"
else
  bad "r1: expected exactly one run directory under DEEP_RESEARCH_DEV_ARTIFACT_ROOT, found $r1_count"
fi
r1_run="$(find "$TMP/default-artifacts" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed -n '1p' || true)"
if [[ -n "$r1_run" && -f "$r1_run/cell.md" ]]; then
  check "r1: cell.md extracted under default artifact root" "$TMP/a.expected" "$r1_run/cell.md"
else
  bad "r1: no cell.md under default artifact root (run dir: ${r1_run:-none})"
fi

# r2: vault rejection — output-dir inside the resolved vault exits 2 with the
#     guard message, writes nothing, and never invokes grok (stub marker file
#     must stay absent)
mkdir -p "$TMP/vault"
rm -f "$TMP/grok-called-vault"
r2_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-vault" \
  PATH="$TMP/bin:$PATH" DEEP_RESEARCH_DEV_VAULT_ROOT="$TMP/vault" \
  bash "$SMOKE" "test query vault-reject" "$TMP/vault/forbidden-run" \
  >"$TMP/run-vault.log" 2>&1 || r2_rc=$?
if [[ "$r2_rc" -eq 2 ]]; then
  ok "r2: vault-child output-dir rejected with exit 2"
else
  bad "r2: expected exit 2 for vault-child output-dir, got $r2_rc (see $TMP/run-vault.log)"
fi
if grep -Fq 'must not be inside SkillWiki vault' "$TMP/run-vault.log"; then
  ok "r2: guard error message present"
else
  bad "r2: guard error message missing from $TMP/run-vault.log"
fi
if [[ ! -e "$TMP/vault/forbidden-run/cell.full.md" ]]; then
  ok "r2: no cell.full.md written for rejected run"
else
  bad "r2: cell.full.md written despite vault rejection"
fi
if [[ ! -e "$TMP/grok-called-vault" ]]; then
  ok "r2: stub grok not invoked"
else
  bad "r2: stub grok invoked despite vault rejection"
fi

# r3: pretty/multiline JSON vault root — regression for the reviewer finding.
#     The old single-line sed JSON parse cannot see a "path" value when the
#     key and value span lines, so resolution failed and the guard was
#     skipped. A stub `skillwiki` (before PATH) emits a multiline JSON shape;
#     the real harness must still reject $TMP/vault/forbidden-json-run with
#     exit 2, create nothing, and never invoke grok.
mkdir -p "$TMP/vault"
cat > "$TMP/bin/skillwiki" <<EOF
#!/usr/bin/env bash
cat <<'JSON'
{
  "ok": true,
  "data": {
    "path":
    "$TMP/vault"
  }
}
JSON
EOF
chmod +x "$TMP/bin/skillwiki"
rm -f "$TMP/grok-called-json"
r3_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-json" \
  PATH="$TMP/bin:$PATH" \
  env -u DEEP_RESEARCH_DEV_VAULT_ROOT -u DEEP_RESEARCH_DEV_ARTIFACT_ROOT \
  bash "$SMOKE" "test query json-vault" "$TMP/vault/forbidden-json-run" \
  >"$TMP/run-json.log" 2>&1 || r3_rc=$?
if [[ "$r3_rc" -eq 2 ]]; then
  ok "r3: multiline-JSON vault resolved, rejected with exit 2"
else
  bad "r3: expected exit 2 for JSON vault-child output-dir, got $r3_rc (see $TMP/run-json.log)"
fi
if grep -Fq 'must not be inside SkillWiki vault' "$TMP/run-json.log"; then
  ok "r3: guard error message present (JSON-resolved vault)"
else
  bad "r3: guard error message missing from $TMP/run-json.log"
fi
if [[ ! -e "$TMP/vault/forbidden-json-run" ]]; then
  ok "r3: no output directory created for rejected JSON run"
else
  bad "r3: output directory created despite JSON vault rejection"
fi
if [[ ! -e "$TMP/grok-called-json" ]]; then
  ok "r3: stub grok not invoked (JSON vault)"
else
  bad "r3: stub grok invoked despite JSON vault rejection"
fi

# r4: vault-resolver failure must fail closed (task 10a). A stub `skillwiki`
#     (first on PATH) fails both `path --plain` and `path` with empty stdout,
#     stderr noise, and exit 1. The shipped guard treats resolution failure as
#     "no vault" and proceeds to mkdir/grok, so every assertion here is RED on
#     the current harness; the fix must exit 3 with a vault-resolution/boundary
#     diagnostic, create no output dir, and never invoke grok.
mkdir -p "$TMP/bin-r4"
cat > "$TMP/bin-r4/skillwiki" <<'EOF'
#!/usr/bin/env bash
echo "skillwiki: cannot resolve vault (simulated resolver failure)" >&2
exit 1
EOF
chmod +x "$TMP/bin-r4/skillwiki"
rm -rf "$TMP/out-r4"
rm -f "$TMP/grok-called-r4"
r4_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-r4" \
  PATH="$TMP/bin-r4:$TMP/bin:$PATH" \
  env -u DEEP_RESEARCH_DEV_VAULT_ROOT -u DEEP_RESEARCH_DEV_ARTIFACT_ROOT \
  bash "$SMOKE" "test query resolver-fail" "$TMP/out-r4" \
  >"$TMP/run-r4.log" 2>&1 || r4_rc=$?
if [[ "$r4_rc" -eq 3 ]]; then
  ok "r4: vault-resolver failure fails closed with exit 3"
else
  bad "r4: expected exit 3 when vault resolver fails, got $r4_rc (see $TMP/run-r4.log)"
fi
if grep -Eiq 'skillwiki.{0,40}vault|vault.{0,40}(resol|boundary)|boundary guard' "$TMP/run-r4.log"; then
  ok "r4: diagnostic names SkillWiki vault resolution / boundary guard"
else
  bad "r4: no vault-resolution/boundary diagnostic in $TMP/run-r4.log"
fi
if [[ ! -e "$TMP/out-r4" ]]; then
  ok "r4: no output directory created"
else
  bad "r4: output directory created despite vault-resolver failure"
fi
if [[ ! -e "$TMP/grok-called-r4" ]]; then
  ok "r4: stub grok not invoked"
else
  bad "r4: stub grok invoked despite vault-resolver failure"
fi

# r5: containment-probe failure must fail closed (task 10a). The stub
#     `skillwiki` returns a valid bare vault path outside the supplied output
#     dir; a stub `python3` (first on PATH) exits 42 only for the probe form
#     `python3 - <candidate> <parent>` and delegates every other invocation to
#     the real interpreter (resolved before PATH is modified). The shipped
#     guard reads probe failure as "not inside vault" and proceeds to
#     mkdir/grok, so every assertion here is RED on the current harness; the
#     fix must exit 3 with a boundary/probe diagnostic, create no output dir,
#     and never invoke grok.
REAL_PY="$(command -v python3)"
mkdir -p "$TMP/bin-r5"
cat > "$TMP/bin-r5/skillwiki" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$TMP/vault-r5"
EOF
chmod +x "$TMP/bin-r5/skillwiki"
cat > "$TMP/bin-r5/python3" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "-" && \$# -eq 3 ]]; then
  exit 42
fi
exec "$REAL_PY" "\$@"
EOF
chmod +x "$TMP/bin-r5/python3"
rm -rf "$TMP/out-r5"
rm -f "$TMP/grok-called-r5"
# Restore r5's probe-stage coverage (task 10d): the strict resolver requires
# the resolved root to be an existing directory, so create $TMP/vault-r5
# before the harness run. The stub's bare resolver output then passes root
# validation and the run reaches the python3 probe stub (exit 42) instead of
# failing earlier as a resolver-stage fallback.
mkdir -p "$TMP/vault-r5"
r5_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-r5" \
  PATH="$TMP/bin-r5:$TMP/bin:$PATH" \
  env -u DEEP_RESEARCH_DEV_VAULT_ROOT -u DEEP_RESEARCH_DEV_ARTIFACT_ROOT \
  bash "$SMOKE" "test query probe-fail" "$TMP/out-r5" \
  >"$TMP/run-r5.log" 2>&1 || r5_rc=$?
if [[ "$r5_rc" -eq 3 ]]; then
  ok "r5: containment-probe failure fails closed with exit 3"
else
  bad "r5: expected exit 3 when containment probe fails, got $r5_rc (see $TMP/run-r5.log)"
fi
if grep -Eiq 'boundary|containment probe|probe.{0,20}(fail|error)|python.{0,20}(fail|error)' "$TMP/run-r5.log"; then
  ok "r5: diagnostic names boundary/probe failure"
else
  bad "r5: no boundary/probe diagnostic in $TMP/run-r5.log"
fi
if [[ ! -e "$TMP/out-r5" ]]; then
  ok "r5: no output directory created"
else
  bad "r5: output directory created despite probe failure"
fi
if [[ ! -e "$TMP/grok-called-r5" ]]; then
  ok "r5: stub grok not invoked"
else
  bad "r5: stub grok invoked despite probe failure"
fi

# r6: containment-probe failure with the ORDINARY Python exception exit code 1
#     must fail closed (task 10c). The Sonnet review found the first guard
#     repair still treats probe exit 1 as the normal "outside vault" verdict,
#     but an unexpected Python exception also exits 1. Like r5, a stub
#     `skillwiki` (first on PATH) returns an existing valid bare vault path
#     outside the explicit output dir; a stub `python3` (first on PATH) exits 1
#     — the same code a normal Python exception would produce — only for the
#     probe form `python3 - <candidate> <parent>` and delegates every other
#     invocation to the real interpreter (resolved before PATH is modified).
#     The shipped guard reads probe exit 1 as "outside" and proceeds to
#     mkdir/grok, so every assertion here is RED on the current harness; the
#     fix must exit 3 with a boundary/probe diagnostic, create no output dir,
#     and never invoke grok.
mkdir -p "$TMP/vault-r6"
mkdir -p "$TMP/bin-r6"
cat > "$TMP/bin-r6/skillwiki" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$TMP/vault-r6"
EOF
chmod +x "$TMP/bin-r6/skillwiki"
cat > "$TMP/bin-r6/python3" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "-" && \$# -eq 3 ]]; then
  exit 1
fi
exec "$REAL_PY" "\$@"
EOF
chmod +x "$TMP/bin-r6/python3"
rm -rf "$TMP/out-r6"
rm -f "$TMP/grok-called-r6"
r6_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-r6" \
  PATH="$TMP/bin-r6:$TMP/bin:$PATH" \
  env -u DEEP_RESEARCH_DEV_VAULT_ROOT -u DEEP_RESEARCH_DEV_ARTIFACT_ROOT \
  bash "$SMOKE" "test query probe-exit1" "$TMP/out-r6" \
  >"$TMP/run-r6.log" 2>&1 || r6_rc=$?
if [[ "$r6_rc" -eq 3 ]]; then
  ok "r6: probe exit 1 (ordinary exception code) fails closed with exit 3"
else
  bad "r6: expected exit 3 when containment probe exits 1, got $r6_rc (see $TMP/run-r6.log)"
fi
if grep -Eiq 'boundary|containment probe|probe.{0,20}(fail|error)|python.{0,20}(fail|error)' "$TMP/run-r6.log"; then
  ok "r6: diagnostic names boundary/probe failure"
else
  bad "r6: no boundary/probe diagnostic in $TMP/run-r6.log"
fi
if [[ ! -e "$TMP/out-r6" ]]; then
  ok "r6: no output directory created"
else
  bad "r6: output directory created despite probe exit 1"
fi
if [[ ! -e "$TMP/grok-called-r6" ]]; then
  ok "r6: stub grok not invoked"
else
  bad "r6: stub grok invoked despite probe exit 1"
fi

# r7: unrecognized nonempty `skillwiki` output must fail closed (task 10c).
#     The resolver accepts any nonempty non-JSON output as a vault root: a
#     stub `skillwiki` (first on PATH) prints `skillwiki unrecognized output`
#     and exits 0 for both `path --plain` and `path`. Ordinary Python runs
#     the containment probe against the bogus root (a relative path that
#     resolves outside the explicit output dir), so the shipped guard
#     "confirms" the output dir is outside and proceeds to mkdir/grok. Every
#     assertion here is RED on the current code; the fix must reject
#     unrecognized resolver output with exit 3 and a
#     vault-resolution/boundary diagnostic, create no output dir, and never
#     invoke grok.
mkdir -p "$TMP/bin-r7"
cat > "$TMP/bin-r7/skillwiki" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'skillwiki unrecognized output'
exit 0
EOF
chmod +x "$TMP/bin-r7/skillwiki"
rm -rf "$TMP/out-r7"
rm -f "$TMP/grok-called-r7"
r7_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-r7" \
  PATH="$TMP/bin-r7:$TMP/bin:$PATH" \
  env -u DEEP_RESEARCH_DEV_VAULT_ROOT -u DEEP_RESEARCH_DEV_ARTIFACT_ROOT \
  bash "$SMOKE" "test query resolver-garbage" "$TMP/out-r7" \
  >"$TMP/run-r7.log" 2>&1 || r7_rc=$?
if [[ "$r7_rc" -eq 3 ]]; then
  ok "r7: unrecognized resolver output fails closed with exit 3"
else
  bad "r7: expected exit 3 for unrecognized resolver output, got $r7_rc (see $TMP/run-r7.log)"
fi
if grep -Eiq 'skillwiki.{0,40}vault|vault.{0,40}(resol|boundary)|boundary guard' "$TMP/run-r7.log"; then
  ok "r7: diagnostic names SkillWiki vault resolution / boundary guard"
else
  bad "r7: no vault-resolution/boundary diagnostic in $TMP/run-r7.log"
fi
if [[ ! -e "$TMP/out-r7" ]]; then
  ok "r7: no output directory created"
else
  bad "r7: output directory created despite unrecognized resolver output"
fi
if [[ ! -e "$TMP/grok-called-r7" ]]; then
  ok "r7: stub grok not invoked"
else
  bad "r7: stub grok invoked despite unrecognized resolver output"
fi

# r8: explicit RELATIVE vault override must fail closed (task 10d). The
#     resolver's override branch returns DEEP_RESEARCH_DEV_VAULT_ROOT
#     verbatim with no validation, so `relative-vault` becomes the vault
#     root, the real containment probe resolves it against the process cwd
#     and answers "outside", and the harness proceeds to mkdir/grok. Every
#     assertion here is RED on the current harness; the fix must apply the
#     same validity contract as other resolved roots (absolute, existing
#     directory) and exit 3 with a vault-resolution/boundary diagnostic
#     before creating anything or invoking grok.
rm -rf "$TMP/out-r8"
rm -f "$TMP/grok-called-r8"
r8_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-r8" \
  PATH="$TMP/bin:$PATH" \
  env -u DEEP_RESEARCH_DEV_ARTIFACT_ROOT \
  DEEP_RESEARCH_DEV_VAULT_ROOT=relative-vault \
  bash "$SMOKE" "test query relative-override" "$TMP/out-r8" \
  >"$TMP/run-r8.log" 2>&1 || r8_rc=$?
if [[ "$r8_rc" -eq 3 ]]; then
  ok "r8: relative vault override fails closed with exit 3"
else
  bad "r8: expected exit 3 for relative vault override, got $r8_rc (see $TMP/run-r8.log)"
fi
if grep -Eiq 'skillwiki.{0,40}vault|vault.{0,40}(resol|boundary)|boundary guard' "$TMP/run-r8.log"; then
  ok "r8: diagnostic names SkillWiki vault resolution / boundary guard"
else
  bad "r8: no vault-resolution/boundary diagnostic in $TMP/run-r8.log"
fi
if [[ ! -e "$TMP/out-r8" ]]; then
  ok "r8: no output directory created"
else
  bad "r8: output directory created despite relative vault override"
fi
if [[ ! -e "$TMP/grok-called-r8" ]]; then
  ok "r8: stub grok not invoked"
else
  bad "r8: stub grok invoked despite relative vault override"
fi

# r9: explicit nonexistent ABSOLUTE vault override must fail closed (task
#     10d). DEEP_RESEARCH_DEV_VAULT_ROOT points at a path that is never
#     created ($TMP/nonexistent-override-vault); the resolver returns it
#     verbatim, the real containment probe answers "outside" (resolve() does
#     not require existence), and the harness proceeds to mkdir/grok. Every
#     assertion here is RED on the current harness; the fix must reject a
#     non-directory override with exit 3 and a vault-resolution/boundary
#     diagnostic before creating anything or invoking grok.
rm -rf "$TMP/out-r9"
rm -f "$TMP/grok-called-r9"
r9_rc=0
GROK_STUB_OUTPUT="$TMP/a.full" GROK_STUB_EXIT=0 GROK_STUB_CALLED="$TMP/grok-called-r9" \
  PATH="$TMP/bin:$PATH" \
  env -u DEEP_RESEARCH_DEV_ARTIFACT_ROOT \
  DEEP_RESEARCH_DEV_VAULT_ROOT="$TMP/nonexistent-override-vault" \
  bash "$SMOKE" "test query nonexistent-override" "$TMP/out-r9" \
  >"$TMP/run-r9.log" 2>&1 || r9_rc=$?
if [[ "$r9_rc" -eq 3 ]]; then
  ok "r9: nonexistent absolute vault override fails closed with exit 3"
else
  bad "r9: expected exit 3 for nonexistent absolute vault override, got $r9_rc (see $TMP/run-r9.log)"
fi
if grep -Eiq 'skillwiki.{0,40}vault|vault.{0,40}(resol|boundary)|boundary guard' "$TMP/run-r9.log"; then
  ok "r9: diagnostic names SkillWiki vault resolution / boundary guard"
else
  bad "r9: no vault-resolution/boundary diagnostic in $TMP/run-r9.log"
fi
if [[ ! -e "$TMP/out-r9" ]]; then
  ok "r9: no output directory created"
else
  bad "r9: output directory created despite nonexistent vault override"
fi
if [[ ! -e "$TMP/grok-called-r9" ]]; then
  ok "r9: stub grok not invoked"
else
  bad "r9: stub grok invoked despite nonexistent vault override"
fi

# ---- summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
