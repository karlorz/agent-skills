#!/bin/bash
# Hermetic regression tests for the portfolio-lab profile.
# Stubs ssh/rsync and the Portfolio Lab recovery bootstrap; never connects to
# live hosts and never touches real config (XDG_CONFIG_HOME is redirected).
# The Portfolio Lab recovery CLI contract is authoritative: the wrappers must
# not invent a `backup` or `--no-activate`/`--activate` surface, must run
# canonical `verify --archive` after retrieval, must restore with canonical
# `restore --archive --app-dir --web-root --target-mode dev|prod [...]` using
# the bootstrap packaged in the archive, and must never auto-activate
# production (manual `activate-prod` command is printed only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_CLI="$SKILL_DIR/scripts/host-backup-cli.sh"
RESTORE_CLI="$SKILL_DIR/scripts/host-restore-cli.sh"
BACKUP_HOST="$SKILL_DIR/scripts/backup-host.sh"
PORTFOLIO_BACKUP="$SKILL_DIR/scripts/portfolio-lab-backup.sh"
PORTFOLIO_RESTORE="$SKILL_DIR/scripts/portfolio-lab-restore.sh"
PROFILES_SH="$SKILL_DIR/scripts/profiles.sh"
SKILL_DOC="$SKILL_DIR/skills/host-backup-restore/SKILL.md"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  shift
  if "$@"; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# run_ok <desc> <command...> — command must exit 0; output captured
run_ok() {
  local desc="$1"
  shift
  local out rc
  out="$("$@" 2>&1)" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (exit=$rc)"
    printf '%s\n' "$out" | head -10
    FAIL=$((FAIL + 1))
  fi
}

# run_fail <desc> <pattern> <command...> — command must exit non-zero and
# print <pattern>; output captured
run_fail() {
  local desc="$1" pattern="$2"
  shift 2
  local out rc
  out="$("$@" 2>&1)" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -Fq -- "$pattern"; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (exit=$rc, want failure containing '$pattern')"
    printf '%s\n' "$out" | head -10
    FAIL=$((FAIL + 1))
  fi
}

# ── Fixtures ──────────────────────────────────────────────────────────────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-portfolio-lab.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Fake "remote" staging dir that the stubbed ssh/rsync operate on.
FAKE_REMOTE_DIR="$TMP/remote_stage"
mkdir -p "$FAKE_REMOTE_DIR"

# Stub ssh: records commands; emulates the target for commands that operate on
# the portfolio-lab restore staging dir by translating the remote path to the
# fake remote dir and evaluating locally.
REMOTE_STAGE_SUFFIX="stage"
STUBBIN="$TMP/bin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/ssh" <<'SH'
#!/bin/bash
set -euo pipefail
cmd="${!#}"
echo "ssh: $cmd" >> "$SSH_STUB_LOG"
if [[ "$cmd" == *"mktemp -d /tmp/portfolio-lab-restore.XXXXXX"* ]]; then
  printf '/tmp/portfolio-lab-restore.%s\n' "$REMOTE_STAGE_SUFFIX"
  exit 0
fi
if [[ "$cmd" != *"$REMOTE_MARKER"* ]]; then
  exit 0
fi
translated="${cmd//$REMOTE_MARKER/$FAKE_REMOTE_DIR}"
if [[ "$cmd" == *"chmod 700"* ]]; then
  eval "mkdir -p ${translated#chmod 700 }"
fi
eval "$translated"
SH
chmod +x "$STUBBIN/ssh"

# Stub rsync: records args and copies local sources to a local or fake-remote
# destination (emulates the transfer; never touches the network).
cat > "$STUBBIN/rsync" <<'SH'
#!/bin/bash
set -euo pipefail
echo "rsync: $*" >> "$RSYNC_STUB_LOG"
args=("$@")
srcs=()
i=0
while [ "$i" -lt "${#args[@]}" ]; do
  a="${args[$i]}"
  case "$a" in
    -e) i=$((i + 2)); continue ;;
    -*) i=$((i + 1)); continue ;;
    *) srcs+=("$a") ;;
  esac
  i=$((i + 1))
done
n="${#srcs[@]}"
dst="${srcs[$((n - 1))]}"
srcs=("${srcs[@]:0:$((n - 1))}")
if [[ "$dst" == *:* ]]; then
  remotedir="${dst#*:}"
  remotedir="${remotedir//$REMOTE_MARKER/$FAKE_REMOTE_DIR}"
  mkdir -p "$remotedir"
  for s in "${srcs[@]}"; do cp "$s" "$remotedir/"; done
else
  mkdir -p "$dst"
  for s in "${srcs[@]}"; do cp "$s" "$dst/"; done
fi
SH
chmod +x "$STUBBIN/rsync"

# Fake recovery bootstrap: records its invocation (via
# PORTFOLIO_LAB_TEST_LOG) instead of doing real work.
FAKE_BOOTSTRAP() {
  cat <<'PY'
#!/usr/bin/env python3
"""Fake Portfolio Lab recovery CLI bootstrap used by hermetic tests."""
import os
import sys

log = os.environ.get("PORTFOLIO_LAB_TEST_LOG", "")
if log:
    with open(log, "a") as fh:
        fh.write(" ".join(sys.argv[1:]) + "\n")
PY
}

# Build a canonical Portfolio Lab archive: plaintext .tar with embedded
# recovery-manifest.json and the verified bootstrap at tools/. Variants:
# "" good | "no-bootstrap" | "no-manifest". Exact member names (no "./"
# prefix) per the authoritative contract.
build_archive() {
  local archive="$1" variant="$2"
  local stage="$TMP/stage-$variant"
  rm -rf "$stage"
  mkdir -p "$stage/tools"
  if [ "$variant" != "no-bootstrap" ]; then
    FAKE_BOOTSTRAP > "$stage/tools/portfolio_lab_recovery.py"
  fi
  if [ "$variant" != "no-manifest" ]; then
    printf '{"format":"portfolio-lab-recovery","bootstrap":"tools/portfolio_lab_recovery.py"}\n' \
      > "$stage/recovery-manifest.json"
  fi
  printf 'payload\n' > "$stage/data.txt"
  local members="tools/portfolio_lab_recovery.py recovery-manifest.json data.txt"
  if [ "$variant" = "no-bootstrap" ]; then
    members="recovery-manifest.json data.txt"
  fi
  if [ "$variant" = "no-manifest" ]; then
    members="tools/portfolio_lab_recovery.py data.txt"
  fi
  # shellcheck disable=SC2086
  tar cf "$archive" -C "$stage" $members
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$archive" > "$archive.sha256"
  else
    shasum -a 256 "$archive" > "$archive.sha256"
  fi
}

# Unsafe archive fixtures: the required members are present but the archive
# also carries a dangerous member (traversal, absolute path, symlink), or it
# is not a tar at all. Sidecars are valid so the gate under test is the safe
# stdlib extraction, not the checksum.
build_bad_archive() {
  local archive="$1" kind="$2"
  PORTFOLIO_LAB_FAKE_BOOTSTRAP="$(FAKE_BOOTSTRAP)" python3 - "$archive" "$kind" <<'PY'
import io
import os
import sys
import tarfile

archive, kind = sys.argv[1], sys.argv[2]
bootstrap = os.environ.get("PORTFOLIO_LAB_FAKE_BOOTSTRAP", "#!/usr/bin/env python3\n")


def add_file(tf, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    tf.addfile(info, io.BytesIO(data))


with tarfile.open(archive, "w") as tf:
    add_file(tf, "recovery-manifest.json", b'{"format":"portfolio-lab-recovery"}')
    add_file(tf, "tools/portfolio_lab_recovery.py", bootstrap.encode("utf-8"))
    if kind == "traversal":
        add_file(tf, "../evil.txt", b"evil")
    elif kind == "absolute":
        add_file(tf, "/etc/evil.txt", b"evil")
    elif kind == "symlink":
        link = tarfile.TarInfo("tools/evil-link")
        link.type = tarfile.SYMTYPE
        link.linkname = "/etc/passwd"
        tf.addfile(link)
    elif kind == "duplicate-bootstrap":
        add_file(tf, "tools/portfolio_lab_recovery.py", b"#!/usr/bin/env python3\nraise SystemExit(99)\n")
    elif kind == "duplicate-manifest":
        add_file(tf, "recovery-manifest.json", b'{"duplicate":true}')
    elif kind == "manifest-directory":
        directory = tarfile.TarInfo("recovery-manifest.json")
        directory.type = tarfile.DIRTYPE
        tf.addfile(directory)
    elif kind == "hardlink":
        link = tarfile.TarInfo("tools/hard-link")
        link.type = tarfile.LNKTYPE
        link.linkname = "tools/portfolio_lab_recovery.py"
        tf.addfile(link)
    elif kind == "fifo":
        fifo = tarfile.TarInfo("tools/fifo")
        fifo.type = tarfile.FIFOTYPE
        tf.addfile(fifo)
    elif kind == "backslash":
        add_file(tf, "tools\\evil.py", b"evil")
    elif kind == "drive":
        add_file(tf, "C:/evil.txt", b"evil")
PY
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$archive" > "$archive.sha256"
  else
    shasum -a 256 "$archive" > "$archive.sha256"
  fi
}

archive_sha256() {
  local archive="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$archive" | awk '{print $1}'
  else
    shasum -a 256 "$archive" | awk '{print $1}'
  fi
}

ARCHIVE_GOOD="$TMP/portfolio-lab-good.portfolio-lab-recovery.tar"
ARCHIVE_NO_BOOTSTRAP="$TMP/portfolio-lab-no-bootstrap.portfolio-lab-recovery.tar"
ARCHIVE_NO_MANIFEST="$TMP/portfolio-lab-no-manifest.portfolio-lab-recovery.tar"
ARCHIVE_NO_SIDECAR="$TMP/portfolio-lab-no-sidecar.portfolio-lab-recovery.tar"
ARCHIVE_TRAVERSAL="$TMP/portfolio-lab-traversal.portfolio-lab-recovery.tar"
ARCHIVE_ABSOLUTE="$TMP/portfolio-lab-absolute.portfolio-lab-recovery.tar"
ARCHIVE_SYMLINK="$TMP/portfolio-lab-symlink.portfolio-lab-recovery.tar"
ARCHIVE_DUPLICATE_BOOTSTRAP="$TMP/portfolio-lab-duplicate-bootstrap.portfolio-lab-recovery.tar"
ARCHIVE_DUPLICATE_MANIFEST="$TMP/portfolio-lab-duplicate-manifest.portfolio-lab-recovery.tar"
ARCHIVE_MANIFEST_DIRECTORY="$TMP/portfolio-lab-manifest-directory.portfolio-lab-recovery.tar"
ARCHIVE_HARDLINK="$TMP/portfolio-lab-hardlink.portfolio-lab-recovery.tar"
ARCHIVE_FIFO="$TMP/portfolio-lab-fifo.portfolio-lab-recovery.tar"
ARCHIVE_BACKSLASH="$TMP/portfolio-lab-backslash.portfolio-lab-recovery.tar"
ARCHIVE_DRIVE="$TMP/portfolio-lab-drive.portfolio-lab-recovery.tar"
ARCHIVE_MALFORMED="$TMP/portfolio-lab-malformed.portfolio-lab-recovery.tar"
ARCHIVE_GZ="$TMP/portfolio-lab-good.portfolio-lab-recovery.tar.gz"
build_archive "$ARCHIVE_GOOD" ""
build_archive "$ARCHIVE_NO_BOOTSTRAP" "no-bootstrap"
build_archive "$ARCHIVE_NO_MANIFEST" "no-manifest"
# Archive with NO checksum sidecar next to it (sidecar deliberately removed).
build_archive "$ARCHIVE_NO_SIDECAR" ""
rm -f "$ARCHIVE_NO_SIDECAR.sha256"
build_bad_archive "$ARCHIVE_TRAVERSAL" "traversal"
build_bad_archive "$ARCHIVE_ABSOLUTE" "absolute"
build_bad_archive "$ARCHIVE_SYMLINK" "symlink"
build_bad_archive "$ARCHIVE_DUPLICATE_BOOTSTRAP" "duplicate-bootstrap"
build_bad_archive "$ARCHIVE_DUPLICATE_MANIFEST" "duplicate-manifest"
build_bad_archive "$ARCHIVE_MANIFEST_DIRECTORY" "manifest-directory"
build_bad_archive "$ARCHIVE_HARDLINK" "hardlink"
build_bad_archive "$ARCHIVE_FIFO" "fifo"
build_bad_archive "$ARCHIVE_BACKSLASH" "backslash"
build_bad_archive "$ARCHIVE_DRIVE" "drive"
printf 'this is not a tar archive\n' > "$ARCHIVE_MALFORMED"
TRUSTED_SHA256=$(archive_sha256 "$ARCHIVE_GOOD")
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$ARCHIVE_MALFORMED" > "$ARCHIVE_MALFORMED.sha256"
else
  shasum -a 256 "$ARCHIVE_MALFORMED" > "$ARCHIVE_MALFORMED.sha256"
fi
# Gzip'd archive: must be rejected (plaintext .tar only).
gzip -c "$ARCHIVE_GOOD" > "$ARCHIVE_GZ"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$ARCHIVE_GZ" > "$ARCHIVE_GZ.sha256"
else
  shasum -a 256 "$ARCHIVE_GZ" > "$ARCHIVE_GZ.sha256"
fi

# Source "storage" for backup retrieval (archive + checksum sidecar).
SRC="$TMP/src"
mkdir -p "$SRC"
cp "$ARCHIVE_GOOD" "$SRC/"
cp "$ARCHIVE_GOOD.sha256" "$SRC/"

XDG_CONFIG_HOME="$TMP/xdg"
RSYNC_STUB_LOG="$TMP/rsync.log"
SSH_STUB_LOG="$TMP/ssh.log"
PORTFOLIO_LAB_TEST_LOG="$TMP/recovery.log"
REMOTE_MARKER="/tmp/portfolio-lab-restore"
: > "$RSYNC_STUB_LOG"
: > "$SSH_STUB_LOG"
: > "$PORTFOLIO_LAB_TEST_LOG"
export XDG_CONFIG_HOME RSYNC_STUB_LOG SSH_STUB_LOG PORTFOLIO_LAB_TEST_LOG REMOTE_MARKER REMOTE_STAGE_SUFFIX FAKE_REMOTE_DIR
export PATH="$STUBBIN:$PATH"

# ── Tests ─────────────────────────────────────────────────────────────────

test_bootstrap_gate_extracts_only_expected_file() {
  local dest="$TMP/direct-bootstrap"
  run_ok "bootstrap gate extracts a canonical bootstrap" \
    python3 "$SKILL_DIR/scripts/portfolio_lab_archive.py" "$ARCHIVE_GOOD" "$dest"
  assert "bootstrap content was extracted from the exact member" \
    grep -q "Fake Portfolio Lab recovery CLI bootstrap" "$dest/portfolio_lab_recovery.py"
  assert "bootstrap mode is owner-only" \
    python3 -c "import os,sys; sys.exit((os.stat(sys.argv[1]).st_mode & 0o777) != 0o700)" "$dest/portfolio_lab_recovery.py"
  assert "gate did not extract the manifest or payload" \
    bash -c "test ! -e \"\$1/recovery-manifest.json\" && test ! -e \"\$1/data.txt\"" _ "$dest"
}

test_profile_resolution() {
  # portfolio-lab is a built-in preset (not YAML-only) that selects ONLY
  # the portfolio_lab group.
  local out
  out="$(XDG_CONFIG_HOME="$TMP/xdg-empty" bash -c '
    source "$1"
    resolve_profile portfolio-lab
    echo "groups=[$PROFILE_GROUPS] tier=[$PROFILE_HERMES_TIER]"
    list_profiles
  ' _ "$PROFILES_SH" 2>&1)" || true
  assert "portfolio-lab profile resolves to ONLY the portfolio_lab group" \
    bash -c "[[ \"\$1\" == *'groups=[portfolio_lab]'* ]]" _ "$out"
  assert "portfolio-lab is a built-in preset (listed)" \
    bash -c "printf '%s' \"\$1\" | grep -q 'portfolio-lab'" _ "$out"
}

test_profile_isolation() {
  # The portfolio-lab profile cannot mix with generic host/identity/Caddy/
  # Hermes groups.
  assert "portfolio_lab alone is isolated" \
    bash -c '
      source "$1"
      assert_portfolio_lab_isolated portfolio_lab
    ' _ "$PROFILES_SH"
  assert "portfolio_lab + comma-separated generic group is rejected" \
    bash -c '
      source "$1"
      ! assert_portfolio_lab_isolated "portfolio_lab,hermes"
    ' _ "$PROFILES_SH"
  assert "portfolio_lab + space-separated generic group is rejected" \
    bash -c '
      source "$1"
      ! assert_portfolio_lab_isolated "portfolio_lab ssh tailscale"
    ' _ "$PROFILES_SH"
  assert "generic groups without portfolio_lab are allowed" \
    bash -c '
      source "$1"
      assert_portfolio_lab_isolated "hermes databases"
    ' _ "$PROFILES_SH"
}

test_custom_profile_special_characters_are_data() {
  local xdg="$TMP/xdg-special"
  local profile="x'; print('injected'); #"
  local groups="hermes'); print('injected'); #"
  local desc="desc'); print('injected'); #"
  mkdir -p "$xdg/host-backup-restore"
  cat > "$xdg/host-backup-restore/profiles.yaml" <<'YAML'
profiles:
  safe:
    groups: [hermes]
    hermes_tier: standard
    description: "safe profile"
YAML
  local out
  out="$(XDG_CONFIG_HOME="$xdg" bash -c '
    source "$1"
    resolve_profile "$2"
    printf "resolved=%s\\n" "$PROFILE_GROUPS"
    save_profile "$3" "$4" full "$5" || true
  ' _ "$PROFILES_SH" safe "$profile" "$groups" "$desc" 2>&1)" || true
  assert "custom profile strings do not execute Python" \
    bash -c "test ! -f \"\$1/host-backup-restore/injected\"" _ "$xdg"
  assert "custom profile resolves through argument-safe parser" \
    bash -c "printf '%s' \"\$1\" | grep -q 'resolved=hermes'" _ "$out"
}

test_backup_required_flags() {
  run_fail "backup without --source-archive fails" "--source-archive is required" \
    bash "$BACKUP_CLI" --profile portfolio-lab
  run_fail "backup without explicit --dest fails" "--dest is required" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar"
}

test_backup_no_mix() {
  run_fail "portfolio-lab profile + --all is rejected" "cannot be combined" \
    bash "$BACKUP_CLI" --profile portfolio-lab --all \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" --dest "$TMP/out"
  run_fail "--groups portfolio_lab,hermes is rejected" "cannot" \
    bash "$BACKUP_CLI" --host fakehost --groups "portfolio_lab,hermes" \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" --dest "$TMP/out"
  run_fail "--groups portfolio_lab ssh is rejected" "cannot" \
    bash "$BACKUP_CLI" --host fakehost --groups "portfolio_lab ssh" \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" --dest "$TMP/out"
  run_fail "--source-archive without the portfolio_lab group is rejected" \
    "only valid with" \
    bash "$BACKUP_CLI" --host fakehost --groups hermes \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" --dest "$TMP/out"
}

test_backup_rejects_host_and_relative_destination() {
  run_fail "portfolio-lab backup rejects an ignored --host" "--host/--user" \
    bash "$BACKUP_CLI" --host fakehost --profile portfolio-lab \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" \
      --trusted-sha256 "$TRUSTED_SHA256" --dest "$TMP/out-host"
  run_fail "portfolio-lab backup rejects relative --dest before rsync" "absolute path" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" \
      --trusted-sha256 "$TRUSTED_SHA256" --dest relative-output
}


test_backup_rejects_untrusted_source() {
  run_fail "backup requires a trusted archive digest" "--trusted-sha256" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" --dest "$TMP/out-trusted"
  run_fail "backup rejects a mismatched trusted archive digest" "trusted archive digest mismatch" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" --dest "$TMP/out-trusted" \
      --trusted-sha256 "$(printf '0%.0s' {1..64})"
}

test_backup_retrieval_happy_path() {
  local dest="$TMP/out"
  : > "$RSYNC_STUB_LOG"
  : > "$SSH_STUB_LOG"
  : > "$PORTFOLIO_LAB_TEST_LOG"

  # No --host required: portfolio-lab backup does not connect to a host.
  run_ok "portfolio-lab backup retrieves archive + sidecar and runs canonical verify" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" \
      --dest "$dest" --trusted-sha256 "$TRUSTED_SHA256"

  assert "archive retrieved into --dest" test -f "$dest/portfolio-lab-good.portfolio-lab-recovery.tar"
  assert "checksum sidecar retrieved into --dest" \
    test -f "$dest/portfolio-lab-good.portfolio-lab-recovery.tar.sha256"
  assert "retrieval used resumable rsync (--partial-dir)" \
    grep -q -- "--partial-dir=.rsync-partial" "$RSYNC_STUB_LOG"
  assert "retrieval sourced the explicit --source-archive" \
    grep -q "portfolio-lab-good.portfolio-lab-recovery.tar" "$RSYNC_STUB_LOG"
  assert "retrieval made NO ssh connection" \
    bash -c "test ! -s \"\$1\"" _ "$SSH_STUB_LOG"
  assert "canonical verify invoked with --archive" \
    grep -q -- "verify --archive" "$PORTFOLIO_LAB_TEST_LOG"
  assert "canonical retrieval invokes verify, never source archive creation" \
    bash -c "! grep -Eiq '(^|[[:space:]])create([[:space:]]|$)' \"\$1\"" _ "$PORTFOLIO_LAB_TEST_LOG"
  assert "no attestation file (retrieval scope; creation is source-host create)" \
    bash -c "test ! -e \"\$1/portfolio-lab-attestation.txt\"" _ "$dest"
}

test_backup_fails_closed_on_unverifiable_archive() {
  local dest="$TMP/out-nobootstrap"
  run_fail "backup aborts when archive lacks the embedded verify bootstrap" \
    "missing or ambiguous required member" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$ARCHIVE_NO_BOOTSTRAP" --trusted-sha256 "$(archive_sha256 "$ARCHIVE_NO_BOOTSTRAP")" --dest "$dest"
}

test_backup_dry_run() {
  local dest="$TMP/out-dry"
  : > "$RSYNC_STUB_LOG"
  run_ok "portfolio-lab backup --dry-run succeeds without retrieval" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" \
      --dest "$dest" --trusted-sha256 "$TRUSTED_SHA256" --dry-run
  assert "dry-run performs no rsync" bash -c "test ! -s \"\$1\"" _ "$RSYNC_STUB_LOG"
}

test_generic_restore_rejects_portfolio_archive() {
  run_fail "generic restore rejects a Portfolio Lab archive" "only valid with --groups portfolio_lab" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox --all
  run_fail "generic group restore rejects a Portfolio Lab archive" "only valid with --groups portfolio_lab" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox --groups hermes
}

test_restore_required_flags() {
  run_fail "restore without --target-mode fails" "--target-mode" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --app-dir /srv/app --web-root /srv/www --groups portfolio_lab
  run_fail "restore with invalid --target-mode fails" "dev or prod" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode staging --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
  run_fail "restore without --app-dir fails" "--app-dir" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --web-root /srv/www --groups portfolio_lab
  run_fail "restore without --web-root fails" "--web-root" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --groups portfolio_lab
  run_fail "restore with missing sidecar fails" "checksum sidecar" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_NO_SIDECAR" --trusted-sha256 "$(archive_sha256 "$ARCHIVE_NO_SIDECAR")" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
}

test_restore_no_mix() {
  run_fail "restore portfolio_lab,hermes is rejected" "cannot" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups "portfolio_lab,hermes"
  run_fail "restore portfolio_lab,ssh is rejected" "cannot" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups "portfolio_lab,ssh"
  run_fail "restore --all + portfolio_lab is rejected" "cannot be combined" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --all
  run_fail "portfolio-lab restore refuses --restore-identity" "never restores identities" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --restore-identity
  run_fail "portfolio-lab flags without the portfolio_lab group are rejected" \
    "only valid with" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups hermes
}

test_restore_normalizes_groups_and_rejects_unsafe_user() {
  : > "$RSYNC_STUB_LOG"
  run_ok "restore accepts whitespace-padded exclusive portfolio_lab group" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www --groups '  portfolio_lab  ' --dry-run
  run_fail "restore rejects unsafe --user before composing target" "unsafe --user" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox --user 'root;bad' \
      --target-mode dev --app-dir /srv/app --web-root /srv/www --groups portfolio_lab
}


test_restore_rejects_untrusted_archive() {
  run_fail "restore requires a trusted archive digest" "--trusted-sha256" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
  run_fail "restore rejects a mismatched trusted archive digest" "trusted archive digest mismatch" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --trusted-sha256 "$(printf '0%.0s' {1..64})"
}

test_restore_happy_path_dev() {
  : > "$RSYNC_STUB_LOG"
  : > "$SSH_STUB_LOG"
  : > "$PORTFOLIO_LAB_TEST_LOG"
  local out
  out="$(bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox --user agent \
    --target-mode dev --app-dir /srv/app --web-root /srv/www \
    --groups portfolio_lab 2>&1)" || true

  assert "restore dev mode succeeds" \
    bash -c "printf '%s' \"\$1\" | grep -q 'restore complete'" _ "$out"
  assert "restore transferred archive + sidecar together" \
    bash -c "
      grep -q 'portfolio-lab-good.portfolio-lab-recovery.tar' \"\$1\" &&
      grep -q 'portfolio-lab-good.portfolio-lab-recovery.tar.sha256' \"\$1\"
    " _ "$RSYNC_STUB_LOG"
  assert "restore transfer used resumable rsync (--partial-dir)" \
    grep -q -- "--partial-dir=.rsync-partial" "$RSYNC_STUB_LOG"
  assert "checksum verified on target" \
    bash -c "grep -q 'sha256sum' \"\$1\" || grep -q 'shasum -a 256' \"\$1\"" _ "$SSH_STUB_LOG"
  assert "safe stdlib member validation runs on target (no full extraction)" \
    bash -c "
      grep -q \"python3 - \" \"\$1\" &&
      grep -q \"/tools'\" \"\$1\"
    " _ "$SSH_STUB_LOG"
  assert "wrapper never full-extracts the archive on target" \
    bash -c "! grep -q 'tar xf' \"\$1\" && ! grep -q 'tar xzf' \"\$1\"" _ "$SSH_STUB_LOG"
  assert "target canonical verify precedes canonical restore" \
    bash -c '
      v=$(grep -n "verify --archive" "$1" | head -1 | cut -d: -f1)
      r=$(grep -n "restore --archive" "$1" | head -1 | cut -d: -f1)
      [ -n "$v" ] && [ -n "$r" ] && [ "$v" -lt "$r" ]
    ' _ "$SSH_STUB_LOG"
  assert "canonical restore invoked with packaged bootstrap" \
    bash -c "
      grep -q \"python3 portfolio_lab_recovery.py restore --archive\" \"\$1\"
    " _ "$SSH_STUB_LOG"
  assert "canonical restore passes --target-mode dev" \
    bash -c "grep -q -- \"--target-mode 'dev'\" \"\$1\"" _ "$SSH_STUB_LOG"
  assert "canonical restore passes explicit --app-dir/--web-root" \
    bash -c "
      grep -q -- \"--app-dir '/srv/app'\" \"\$1\" &&
      grep -q -- \"--web-root '/srv/www'\" \"\$1\"
    " _ "$SSH_STUB_LOG"
  assert "manual activate-prod command is printed (never run)" \
    bash -c "
      printf '%s' \"\$1\" | grep -q 'activate-prod' &&
      printf '%s' \"\$1\" | grep -q -- '--confirm-authoritative-activation' &&
      printf '%s' \"\$1\" | grep -q -- '--former-authority-confirmed-stopped'
    " _ "$out"
  assert "manual activation staging remains usable after successful restore" \
    bash -c "test -f \"\$1.stage/portfolio-lab-good.portfolio-lab-recovery.tar\" && test -f \"\$1.stage/tools/portfolio_lab_recovery.py\"" _ "$FAKE_REMOTE_DIR"
  assert "remote staging is owner-only" \
    python3 -c "import os,sys; sys.exit((os.stat(sys.argv[1]).st_mode & 0o777) != 0o700)" "$FAKE_REMOTE_DIR.stage"
  assert "successful restore prints retained staging and cleanup guidance" \
    bash -c "printf '%s' \"\$1\" | grep -q 'Staging retained' && printf '%s' \"\$1\" | grep -q 'clean up'" _ "$out"
  assert "restore never touches SSH identity material" \
    bash -c "! grep -q 'ssh-config-and-keys' \"\$1\"" _ "$SSH_STUB_LOG"
  assert "restore never touches Caddy config/certs" \
    bash -c "! grep -q 'caddy-config' \"\$1\" && ! grep -q 'ssl-certs' \"\$1\"" _ "$SSH_STUB_LOG"
  assert "restore never touches Hermes agent state" \
    bash -c "! grep -q 'hermes-backup' \"\$1\"" _ "$SSH_STUB_LOG"
  assert "restore never touches Tailscale identity" \
    bash -c "! grep -q 'tailscale-state' \"\$1\"" _ "$SSH_STUB_LOG"
}

test_restore_mode_flag_safety() {
  : > "$SSH_STUB_LOG"
  run_ok "prod restore passes canonical production arguments" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox --user agent \
      --target-mode prod --app-dir /srv/app --web-root /srv/www \
      --tasker-service portfolio-lab-tasker --allow-production-paths \
      --groups portfolio_lab
  assert "prod restore passes --target-mode prod" \
    bash -c "grep -q -- \"--target-mode 'prod'\" \"\$1\"" _ "$SSH_STUB_LOG"
  assert "prod restore passes --allow-production-paths" \
    bash -c "grep -q -- '--allow-production-paths' \"\$1\"" _ "$SSH_STUB_LOG"
  assert "prod restore passes --tasker-service" \
    bash -c "grep -q -- \"--tasker-service 'portfolio-lab-tasker'\" \"\$1\"" _ "$SSH_STUB_LOG"
  assert "prod restore never auto-activates" \
    bash -c "! grep -q -- '--activate' \"\$1\"" _ "$SSH_STUB_LOG"
  run_fail "prod restore rejects --start-dev-api" "only valid for dev" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode prod --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --start-dev-api
  run_fail "dev restore rejects --allow-production-paths" "only valid for prod" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --allow-production-paths
}

test_restore_fails_closed_on_invalid_archive() {
  local no_bootstrap_sha no_manifest_sha
  no_bootstrap_sha=$(archive_sha256 "$ARCHIVE_NO_BOOTSTRAP")
  no_manifest_sha=$(archive_sha256 "$ARCHIVE_NO_MANIFEST")
  run_fail "restore aborts when archive lacks the packaged bootstrap" "missing or ambiguous required member" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_NO_BOOTSTRAP" --trusted-sha256 "$no_bootstrap_sha" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
  run_fail "restore aborts when archive lacks recovery-manifest.json" "missing or ambiguous required member" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_NO_MANIFEST" --trusted-sha256 "$no_manifest_sha" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
}

test_backup_rejects_unsafe_archives() {
  local dest="$TMP/out-unsafe" archive
  : > "$PORTFOLIO_LAB_TEST_LOG"
  for archive in "$ARCHIVE_TRAVERSAL" "$ARCHIVE_ABSOLUTE" "$ARCHIVE_SYMLINK" \
    "$ARCHIVE_DUPLICATE_BOOTSTRAP" "$ARCHIVE_DUPLICATE_MANIFEST" "$ARCHIVE_MANIFEST_DIRECTORY" \
    "$ARCHIVE_HARDLINK" "$ARCHIVE_FIFO" "$ARCHIVE_BACKSLASH" "$ARCHIVE_DRIVE"; do
    run_fail "backup aborts on unsafe archive: $(basename "$archive")" "safe archive" \
      bash "$BACKUP_CLI" --profile portfolio-lab --source-archive "$archive" --trusted-sha256 "$(archive_sha256 "$archive")" --dest "$dest"
  done
  assert "unsafe archives never reach canonical verify" \
    bash -c "test ! -s \"\$1\"" _ "$PORTFOLIO_LAB_TEST_LOG"
  run_fail "backup aborts on malformed (non-tar) archive" "cannot open" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$ARCHIVE_MALFORMED" --trusted-sha256 "$(archive_sha256 "$ARCHIVE_MALFORMED")" --dest "$dest"
}

test_restore_rejects_unsafe_archives() {
  local archive
  for archive in "$ARCHIVE_TRAVERSAL" "$ARCHIVE_ABSOLUTE" "$ARCHIVE_SYMLINK" \
    "$ARCHIVE_DUPLICATE_BOOTSTRAP" "$ARCHIVE_DUPLICATE_MANIFEST" "$ARCHIVE_MANIFEST_DIRECTORY" \
    "$ARCHIVE_HARDLINK" "$ARCHIVE_FIFO" "$ARCHIVE_BACKSLASH" "$ARCHIVE_DRIVE"; do
    : > "$SSH_STUB_LOG"
    run_fail "restore aborts on unsafe archive: $(basename "$archive")" "safe archive" \
      bash "$RESTORE_CLI" --archive "$archive" --trusted-sha256 "$(archive_sha256 "$archive")" --target testbox --user agent \
        --target-mode dev --app-dir /srv/app --web-root /srv/www \
        --groups portfolio_lab
    assert "unsafe archive never invokes canonical verify" \
      bash -c "! grep -q 'verify --archive' \"\$1\"" _ "$SSH_STUB_LOG"
    assert "unsafe archive never invokes canonical restore" \
      bash -c "! grep -q 'restore --archive' \"\$1\"" _ "$SSH_STUB_LOG"
    assert "unsafe archive never runs the bootstrap" \
      bash -c "! grep -q 'python3 portfolio_lab_recovery.py' \"\$1\"" _ "$SSH_STUB_LOG"
  done
  : > "$SSH_STUB_LOG"
  run_fail "restore aborts on malformed (non-tar) archive" "cannot open" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_MALFORMED" --trusted-sha256 "$(archive_sha256 "$ARCHIVE_MALFORMED")" --target testbox --user agent \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
  assert "malformed archive never invokes canonical restore" \
    bash -c "! grep -q 'restore --archive' \"\$1\"" _ "$SSH_STUB_LOG"
}

test_restore_failure_cleans_remote_staging() {
  : > "$SSH_STUB_LOG"
  run_fail "gate failure cleans remote staging" "safe archive validation failed" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_DUPLICATE_BOOTSTRAP" --trusted-sha256 "$(archive_sha256 "$ARCHIVE_DUPLICATE_BOOTSTRAP")" --target testbox --user agent \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
  assert "failed restore removes remote staging" \
    bash -c "test ! -e \"\$1.stage\"" _ "$FAKE_REMOTE_DIR"
}

test_restore_argument_safety() {
  run_fail "restore rejects a target beginning with a dash" "unsafe target" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target '-oProxyCommand=touch bad' \
      --target-mode dev --app-dir /srv/app --web-root /srv/www --groups portfolio_lab
  run_fail "restore rejects quote injection in app path" "unsafe --app-dir" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir "/srv/app' ; touch bad" --web-root /srv/www --groups portfolio_lab
  run_fail "restore rejects semicolon injection in web path" "unsafe --web-root" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root '/srv/www; touch bad' --groups portfolio_lab
  run_fail "restore rejects unsafe tasker service name" "unsafe --tasker-service" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www --tasker-service "svc' ; bad" --groups portfolio_lab
  local odd_archive="$TMP/unsafe'archive.tar"
  cp "$ARCHIVE_GOOD" "$odd_archive"
  cp "$ARCHIVE_GOOD.sha256" "$odd_archive.sha256"
  run_fail "restore rejects unsafe archive basename" "unsafe archive filename" \
    bash "$RESTORE_CLI" --archive "$odd_archive" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www --groups portfolio_lab
}

test_restore_dry_run_no_remote_side_effects() {
  : > "$SSH_STUB_LOG"
  : > "$RSYNC_STUB_LOG"
  run_ok "portfolio-lab restore --dry-run succeeds" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox --user agent \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --dry-run
  assert "dry-run makes no ssh calls (no remote cleanup)" \
    bash -c "test ! -s \"\$1\"" _ "$SSH_STUB_LOG"
  assert "dry-run makes no rsync calls" \
    bash -c "test ! -s \"\$1\"" _ "$RSYNC_STUB_LOG"
}

test_plaintext_tar_only() {
  run_fail "backup rejects non-.tar source archive" "unsafe archive filename" \
    bash "$BACKUP_CLI" --profile portfolio-lab \
      --source-archive "$ARCHIVE_GZ" --trusted-sha256 "$(archive_sha256 "$ARCHIVE_GZ")" --dest "$TMP/out-gz"
  run_fail "restore rejects non-.tar archive" "unsafe archive filename" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GZ" --trusted-sha256 "$(archive_sha256 "$ARCHIVE_GZ")" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
}

test_profile_groups_never_silently_overridden() {
  run_fail "--profile portfolio-lab + --groups is rejected" "cannot be combined" \
    bash "$BACKUP_CLI" --profile portfolio-lab --groups hermes
  run_fail "--profile portfolio-lab + --groups portfolio_lab is rejected" "cannot be combined" \
    bash "$BACKUP_CLI" --profile portfolio-lab --groups portfolio_lab
  run_fail "--profile full + --groups portfolio_lab is rejected" "cannot be combined" \
    bash "$BACKUP_CLI" --host fakehost --profile full --groups portfolio_lab
  run_fail "--profile quick + --groups portfolio_lab is rejected" "cannot be combined" \
    bash "$BACKUP_CLI" --host fakehost --profile quick --groups portfolio_lab
}

test_reserved_profile_name() {
  local xdg="$TMP/xdg-l3"
  mkdir -p "$xdg/host-backup-restore"
  cat > "$xdg/host-backup-restore/profiles.yaml" <<'YAML'
profiles:
  portfolio-lab:
    groups: [hermes]
    hermes_tier: full
    description: "malicious override attempt"
YAML
  local out
  out="$(XDG_CONFIG_HOME="$xdg" bash -c '
    source "$1"
    resolve_profile portfolio-lab
    echo "groups=[$PROFILE_GROUPS]"
    if save_profile portfolio-lab hermes; then echo "save=accepted"; else echo "save=rejected"; fi
  ' _ "$PROFILES_SH" 2>&1)" || true
  assert "YAML cannot override the built-in portfolio-lab profile" \
    bash -c "[[ \"\$1\" == *'groups=[portfolio_lab]'* ]]" _ "$out"
  assert "save_profile rejects the reserved built-in name" \
    bash -c "printf '%s' \"\$1\" | grep -q 'save=rejected'" _ "$out"
}

test_backup_rejects_irrelevant_generic_flags() {
  local flag
  for flag in "--user root" "--hermes-tier minimal" "--redetect" "--research" "--save-profile daily" "--db-user postgres" "--db-pass secret"; do
    run_fail "backup rejects silently-ignored generic flag: $flag" "not valid" \
      bash "$BACKUP_CLI" --profile portfolio-lab \
        --source-archive "$SRC/portfolio-lab-good.portfolio-lab-recovery.tar" --trusted-sha256 "$TRUSTED_SHA256" --dest "$TMP/out-l4" $flag
  done
}

test_restore_uses_default_agent_user() {
  : > "$RSYNC_STUB_LOG"
  : > "$SSH_STUB_LOG"
  : > "$PORTFOLIO_LAB_TEST_LOG"
  export REMOTE_MARKER="/tmp/portfolio-lab-restore"
  run_ok "restore defaults to agent@target" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
  assert "restore default target includes agent@host" \
    grep -q "agent@testbox:" "$RSYNC_STUB_LOG"
  export REMOTE_MARKER="/tmp/portfolio-lab-restore"
}

test_restore_forwards_user() {
  : > "$RSYNC_STUB_LOG"
  : > "$SSH_STUB_LOG"
  : > "$PORTFOLIO_LAB_TEST_LOG"
  export REMOTE_MARKER="/tmp/portfolio-lab-restore"
  run_ok "restore forwards --user into the target (user@host)" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox --user root \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab
  export REMOTE_MARKER="/tmp/portfolio-lab-restore-testbox"
  assert "restore target includes user@host" \
    grep -q "root@testbox:" "$RSYNC_STUB_LOG"
}

test_restore_rejects_irrelevant_generic_flags() {
  run_fail "restore rejects --db-user on portfolio-lab path" "not valid" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --db-user postgres
  run_fail "restore rejects --db-pass on portfolio-lab path" "not valid" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --db-pass secret
  run_fail "restore rejects --allow-cross-distro on portfolio-lab path" "not valid" \
    bash "$RESTORE_CLI" --archive "$ARCHIVE_GOOD" --trusted-sha256 "$TRUSTED_SHA256" --target testbox \
      --target-mode dev --app-dir /srv/app --web-root /srv/www \
      --groups portfolio_lab --allow-cross-distro
}

test_backup_host_fails_closed() {
  local manifest="$TMP/manifest.json"
  cat > "$manifest" <<'JSON'
{"hostname": "fakehost", "timestamp": "2026-08-14T00:00:00Z"}
JSON
  run_fail "backup-host.sh fails closed for portfolio_lab (delegated script)" \
    "portfolio-lab-backup.sh" \
    bash "$BACKUP_HOST" "$manifest" portfolio_lab
}

test_help_text() {
  run_ok "portfolio-lab-backup.sh --help exits 0" bash "$PORTFOLIO_BACKUP" --help
  run_ok "portfolio-lab-restore.sh --help exits 0" bash "$PORTFOLIO_RESTORE" --help
  assert "backup help documents --source-archive" \
    bash -c "bash \"\$1\" --help | grep -q -- '--source-archive'" _ "$PORTFOLIO_BACKUP"
  assert "backup help documents --dest" \
    bash -c "bash \"\$1\" --help | grep -q -- '--dest'" _ "$PORTFOLIO_BACKUP"
  assert "backup help documents --trusted-sha256" \
    bash -c "bash \"\$1\" --help | grep -q -- '--trusted-sha256'" _ "$PORTFOLIO_BACKUP"
  assert "restore help documents --trusted-sha256" \
    bash -c "bash \"\$1\" --help | grep -q -- '--trusted-sha256'" _ "$PORTFOLIO_RESTORE"
  assert "backup help documents canonical verify" \
    bash -c "bash \"\$1\" --help | grep -q 'verify --archive'" _ "$PORTFOLIO_BACKUP"
  assert "restore help documents --target-mode" \
    bash -c "bash \"\$1\" --help | grep -q -- '--target-mode'" _ "$PORTFOLIO_RESTORE"
  assert "restore help documents --app-dir/--web-root" \
    bash -c "
      bash \"\$1\" --help | grep -q -- '--app-dir' &&
      bash \"\$1\" --help | grep -q -- '--web-root'
    " _ "$PORTFOLIO_RESTORE"
  assert "host-backup-cli.sh usage documents portfolio-lab flags" \
    bash -c "grep -q -- '--source-archive' \"\$1\" && grep -q -- '--trusted-sha256' \"\$1\"" _ "$BACKUP_CLI"
  assert "host-restore-cli.sh usage documents --target-mode" \
    bash -c "grep -q -- '--target-mode dev|prod' \"\$1\" && grep -q -- '--trusted-sha256' \"\$1\"" _ "$RESTORE_CLI"
}

test_skill_doc_requires_trusted_digest() {
  assert "Portfolio Lab documentation requires --trusted-sha256 for backup and restore" \
    bash -c '
      [ "$(grep -c -- "--trusted-sha256" "$1")" -ge 6 ] &&
      grep -Fq "independently trusted" "$1" &&
      grep -Fq "archive and sidecar are not sufficient" "$1"
    ' _ "$SKILL_DOC"
}

test_no_invented_surface_and_no_generic_logic() {
  assert "backup script never auto-transfers to cloud (no rclone/aws/gcloud)" \
    bash -c "! grep -Eq 'rclone|aws s3|gcloud|s3 cp' \"\$1\"" _ "$PORTFOLIO_BACKUP"
  assert "backup script invokes canonical verify --archive" \
    grep -q "verify --archive" "$PORTFOLIO_BACKUP"
  assert "backup wrapper never executes source archive creation" \
    bash -c "! grep -Ev '^[[:space:]]*#' \"\$1\" | grep -Eq 'portfolio_lab_recovery\\.py[[:space:]]+create'" _ "$PORTFOLIO_BACKUP"
  assert "restore script contains no identity/caddy/hermes restore logic" \
    bash -c "
      ! grep -q 'ssh-config-and-keys' \"\$1\" &&
      ! grep -q 'caddy-config' \"\$1\" &&
      ! grep -q 'hermes-backup.zip' \"\$1\" &&
      ! grep -q 'tailscale-state' \"\$1\"
    " _ "$PORTFOLIO_RESTORE"
  assert "restore script never invents --no-activate/--activate" \
    bash -c "! grep -q -- '--no-activate' \"\$1\" && ! grep -q -- ' --activate' \"\$1\"" \
    _ "$PORTFOLIO_RESTORE"
  assert "backup wrapper never full-extracts the archive" \
    bash -c "! grep -q 'tar xf' \"\$1\" && ! grep -q 'tar xzf' \"\$1\"" _ "$PORTFOLIO_BACKUP"
  assert "restore wrapper never full-extracts the archive" \
    bash -c "! grep -q 'tar xf' \"\$1\" && ! grep -q 'tar xzf' \"\$1\"" _ "$PORTFOLIO_RESTORE"
  assert "CLIs expose no invented --portfolio-lab-repo/--encrypted-at-rest/--activate-prod" \
    bash -c "
      ! grep -q -- '--portfolio-lab-repo' \"\$1\" &&
      ! grep -q -- '--encrypted-at-rest' \"\$1\" &&
      ! grep -q -- '--portfolio-lab-repo' \"\$2\" &&
      ! grep -q -- '--activate-prod' \"\$2\"
    " _ "$BACKUP_CLI" "$RESTORE_CLI"
}

test_bootstrap_gate_extracts_only_expected_file
test_profile_resolution
test_profile_isolation
test_custom_profile_special_characters_are_data
test_profile_groups_never_silently_overridden
test_reserved_profile_name
test_backup_required_flags
test_backup_no_mix
test_backup_rejects_host_and_relative_destination
test_backup_rejects_untrusted_source
test_backup_retrieval_happy_path
test_backup_fails_closed_on_unverifiable_archive
test_backup_rejects_unsafe_archives
test_backup_dry_run
test_generic_restore_rejects_portfolio_archive
test_restore_required_flags

test_restore_no_mix
test_restore_normalizes_groups_and_rejects_unsafe_user
test_restore_rejects_untrusted_archive
test_restore_happy_path_dev
test_restore_mode_flag_safety
test_restore_fails_closed_on_invalid_archive
test_restore_rejects_unsafe_archives
test_restore_failure_cleans_remote_staging
test_restore_argument_safety
test_restore_dry_run_no_remote_side_effects
test_plaintext_tar_only
test_backup_rejects_irrelevant_generic_flags
test_restore_uses_default_agent_user
test_restore_forwards_user
test_restore_rejects_irrelevant_generic_flags
test_backup_host_fails_closed
test_help_text
test_skill_doc_requires_trusted_digest
test_no_invented_surface_and_no_generic_logic

echo "Tests: $PASS passed, $FAIL failed"
test "$FAIL" -eq 0
