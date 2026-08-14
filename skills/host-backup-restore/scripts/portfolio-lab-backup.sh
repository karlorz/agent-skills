#!/bin/bash
# portfolio-lab-backup.sh — Portfolio Lab bundle retrieval (portfolio_lab group)
#
# Retrieves an explicit remote/source archive + checksum sidecar into an
# explicit local --dest with resumable rsync (--partial-dir), verifies the
# checksum, then validates archive members with a stdlib-tarfile safety gate
# (portfolio_lab_archive.py) and extracts ONLY the exact bootstrap regular
# file to controlled staging — the wrapper never full-extracts — before
# running the canonical recovery CLI's `verify --archive` with that packaged
# bootstrap. A separately supplied --trusted-sha256 must match before any
# archive-provided code runs. The sidecar detects transfer corruption but does
# not authenticate an archive supplied by an attacker.
# Plaintext .tar only. No automatic cloud transfer.
#
# Retrieval scope only: this script never claims to create the source archive.
# Creation happens on the source host with the canonical CLI, e.g.:
#   PORTFOLIO_LAB_PROJECT_DIR=<explicit repo> <repo>/scripts/python_runtime.sh \
#     <repo>/scripts/portfolio_lab_recovery.py create \
#     --app-dir <dir> --web-root <dir> --tasker-service <svc> \
#     --archive <remote encrypted path> --storage-encryption-attested
# (PORTFOLIO_LAB_PROJECT_DIR selects the project path for python_runtime.sh.)
#
# Usage:
#   bash portfolio-lab-backup.sh --source-archive PATH --dest PATH --trusted-sha256 HEX [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SOURCE_ARCHIVE=""
DEST=""
TRUSTED_SHA256=""
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: portfolio-lab-backup.sh [options]

Retrieve a Portfolio Lab bundle archive + checksum sidecar from explicit
remote/source storage into an explicit local --dest, validate it with a
stdlib-tarfile safety gate (extracting only the exact bootstrap, never
full-extract), then run the canonical `verify --archive` with that packaged
bootstrap. Plaintext .tar only. Retrieval scope only: the source archive is
created on the source host with the canonical `create` command (see SKILL.md);
this script never creates it.

Options:
  --source-archive PATH  Explicit remote/source archive path (required;
                         local mount path or user@host:path; sidecar is
                         <archive>.sha256)
  --dest PATH            Explicit absolute local retrieval destination (required)
  --trusted-sha256 HEX   Independently trusted 64-character archive SHA-256 (required)
  --dry-run              Print what would be retrieved; write nothing
  -h, --help             Show this help
EOF
}

die() {
  echo "Error: $1" >&2
  exit 1
}

# Portable checksum — macOS uses shasum, Linux uses sha256sum
_compute_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1"
  else
    die "no sha256sum/shasum available"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --source-archive) SOURCE_ARCHIVE="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --trusted-sha256) TRUSTED_SHA256="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage >&2; exit 1 ;;
  esac
done

# ── Required explicit flags ──────────────────────────────────────────────
[ -n "$SOURCE_ARCHIVE" ] || die "--source-archive is required (explicit remote/source archive path)"
[ -n "$DEST" ] || die "--dest is required (explicit local retrieval destination)"
[[ "$DEST" == /* ]] || die "--dest must be an absolute path"
[[ "$TRUSTED_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "--trusted-sha256 must be 64 lowercase hex from an independently trusted source"
command -v rsync >/dev/null 2>&1 || die "rsync is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

ARCHIVE_NAME=$(basename "$SOURCE_ARCHIVE")
SIDECAR_SOURCE="${SOURCE_ARCHIVE}.sha256"

# Plaintext canonical recovery archives only; the strict basename prevents a
# retrieved filename from being confused with a shell argument downstream.
case "$ARCHIVE_NAME" in
  *.portfolio-lab-recovery.tar) ;;
  *) die "unsafe archive filename: require a canonical portfolio-lab recovery .tar" ;;
esac

echo "=== Portfolio Lab Backup (retrieval) ==="
echo "Source archive: $SOURCE_ARCHIVE"
echo "Retrieval dest: $DEST"
echo "Trusted SHA-256: $TRUSTED_SHA256"
echo "Dry run:        $DRY_RUN"
echo ""

if $DRY_RUN; then
  echo "=== DRY RUN ==="
  echo "Would retrieve:"
  echo "  - $SOURCE_ARCHIVE -> $DEST/$ARCHIVE_NAME (rsync --partial-dir)"
  echo "  - $SIDECAR_SOURCE -> $DEST/$ARCHIVE_NAME.sha256"
  echo "  - verify checksum sidecar and independently trusted SHA-256"
  echo "  - validate members + extract exact bootstrap with stdlib tarfile gate (no full extraction)"
  echo "  - run canonical verify: python3 <extracted tools/portfolio_lab_recovery.py> verify --archive $DEST/$ARCHIVE_NAME"
  echo "=== Dry run complete (no files written) ==="
  exit 0
fi

mkdir -p "$DEST"

# Retrieve archive + checksum sidecar with resumable partial transfer.
echo "Retrieving archive..."
rsync -avP --partial-dir=.rsync-partial --timeout=300 "$SOURCE_ARCHIVE" "$DEST/" || die "failed to retrieve archive from $SOURCE_ARCHIVE"
echo "Retrieving checksum sidecar..."
rsync -avP --partial-dir=.rsync-partial --timeout=300 "$SIDECAR_SOURCE" "$DEST/" || die "failed to retrieve checksum sidecar from $SIDECAR_SOURCE"

# Verify checksum before anything else.
SIDECAR="$DEST/$ARCHIVE_NAME.sha256"
expected=$(awk '{print $1}' "$SIDECAR" 2>/dev/null || true)
actual=$(_compute_sha256 "$DEST/$ARCHIVE_NAME" | awk '{print $1}')
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  echo "Error: checksum mismatch for $DEST/$ARCHIVE_NAME (sidecar=$expected, computed=$actual)" >&2
  exit 1
fi
if [ "$TRUSTED_SHA256" != "$actual" ]; then
  echo "Error: trusted archive digest mismatch for $DEST/$ARCHIVE_NAME" >&2
  exit 1
fi
echo "Checksum and trusted digest verified: $actual"

# Safety gate: stdlib tarfile validates every member (no
# traversal/absolute/symlink/device paths; exact required regular-file
# members) and extracts ONLY the exact bootstrap into controlled staging.
# Never full-extract; canonical verify runs only after safe extraction.
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/portfolio-lab-verify.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
python3 "$SCRIPT_DIR/portfolio_lab_archive.py" "$DEST/$ARCHIVE_NAME" "$STAGING" || die "safe archive validation failed for $DEST/$ARCHIVE_NAME (not a safe Portfolio Lab archive)"
echo "Archive members validated; bootstrap extracted to $STAGING"

# Canonical verify with the verified bootstrap packaged in the archive itself
# (never a local repo copy that could differ).
python3 "$STAGING/portfolio_lab_recovery.py" verify --archive "$DEST/$ARCHIVE_NAME" || die "canonical verify failed for $DEST/$ARCHIVE_NAME"
echo "Canonical verify passed: $DEST/$ARCHIVE_NAME"

echo ""
echo "Note: retrieval scope only — this skill does not create the source archive."
echo "Create it on the source host with the canonical CLI (PORTFOLIO_LAB_PROJECT_DIR=<explicit repo>):"
echo "  create --app-dir <dir> --web-root <dir> --tasker-service <svc> --archive <remote encrypted path> --storage-encryption-attested"
echo "=== Portfolio Lab backup complete ==="
