#!/usr/bin/env python3
"""Safely extract the packaged Portfolio Lab recovery bootstrap from a tar.

The host-backup wrapper uses this narrow gate before it runs the archive's
bootstrap. It accepts only an uncompressed tar, validates every member without
extracting it, and writes exactly one bootstrap regular file into a staging
directory. This gate establishes archive safety only; the repository recovery
CLI performs the full manifest and checksum verification afterwards.

Usage:
    portfolio_lab_archive.py ARCHIVE DEST_DIR
"""

from __future__ import annotations

import os
import sys
import tarfile
from collections import Counter
from pathlib import Path

MANIFEST_MEMBER = "recovery-manifest.json"
BOOTSTRAP_MEMBER = "tools/portfolio_lab_recovery.py"
REQUIRED_MEMBERS = (MANIFEST_MEMBER, BOOTSTRAP_MEMBER)
OUTPUT_NAME = "portfolio_lab_recovery.py"
MAX_BOOTSTRAP_BYTES = 10 * 1024 * 1024
CHUNK_BYTES = 1024 * 1024


def fail(message: str) -> None:
    print(f"portfolio_lab_archive.py: {message}", file=sys.stderr)
    raise SystemExit(1)


def safe_member_name(name: str) -> bool:
    if not name or name.startswith("/") or name.startswith("./") or "\\" in name:
        return False
    parts = name.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return False
    if ":" in parts[0] or any(ord(char) < 32 for char in name):
        return False
    return True


def ensure_safe_destination(raw_dest: str) -> Path:
    dest = Path(raw_dest)
    if not dest.is_absolute():
        fail("bootstrap destination must be an absolute controlled staging directory")
    if dest.is_symlink():
        fail(f"bootstrap destination is a symlink: {dest}")
    try:
        dest.mkdir(parents=True, mode=0o700, exist_ok=True)
        os.chmod(dest, 0o700)
    except OSError as exc:
        fail(f"cannot create bootstrap destination: {exc}")
    if not dest.is_dir() or dest.is_symlink():
        fail(f"bootstrap destination is not a safe directory: {dest}")
    output = dest / OUTPUT_NAME
    try:
        if output.exists() or output.is_symlink():
            output.unlink()
    except OSError as exc:
        fail(f"cannot remove stale bootstrap: {exc}")
    return dest


def validate_members(members: list[tarfile.TarInfo]) -> tarfile.TarInfo:
    names = [member.name for member in members]
    counts = Counter(names)
    duplicate = [name for name, count in counts.items() if count != 1]
    if duplicate:
        fail("duplicate archive members: " + ", ".join(sorted(duplicate)[:5]))
    for member in members:
        if not safe_member_name(member.name):
            fail(f"unsafe archive member path: {member.name!r}")
        if not member.isfile() or member.issparse() or member.linkname:
            fail(f"archive member is not a regular file: {member.name!r}")
    for required in REQUIRED_MEMBERS:
        if counts.get(required) != 1:
            fail(f"missing or ambiguous required member: {required}")
    manifest = next(member for member in members if member.name == MANIFEST_MEMBER)
    bootstrap = next(member for member in members if member.name == BOOTSTRAP_MEMBER)
    if not manifest.isfile() or not bootstrap.isfile():
        fail("required manifest/bootstrap members must be regular files")
    if bootstrap.size < 0 or bootstrap.size > MAX_BOOTSTRAP_BYTES:
        fail(f"bootstrap size is unsafe: {bootstrap.size}")
    return bootstrap


def extract_bootstrap(archive: Path, bootstrap: tarfile.TarInfo, dest: Path) -> None:
    output = dest / OUTPUT_NAME
    total = 0
    try:
        with tarfile.open(archive, "r:") as handle:
            source = handle.extractfile(bootstrap)
            if source is None:
                fail("cannot read bootstrap member")
            try:
                with output.open("xb") as target:
                    while True:
                        chunk = source.read(CHUNK_BYTES)
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > MAX_BOOTSTRAP_BYTES:
                            fail("bootstrap exceeds the size limit while reading")
                        target.write(chunk)
            finally:
                source.close()
        if total != bootstrap.size:
            fail("bootstrap member is truncated")
        os.chmod(output, 0o700)
    except (tarfile.TarError, OSError, EOFError, KeyError, ValueError) as exc:
        try:
            output.unlink(missing_ok=True)
        except OSError:
            pass
        fail(f"cannot safely extract bootstrap: {exc}")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        fail("usage: portfolio_lab_archive.py ARCHIVE DEST_DIR")
    archive = Path(argv[1])
    dest = ensure_safe_destination(argv[2])
    try:
        with tarfile.open(archive, "r:") as handle:
            members = handle.getmembers()
    except (tarfile.TarError, OSError, EOFError) as exc:
        fail(f"cannot open as plaintext tar: {exc}")
    bootstrap = validate_members(members)
    extract_bootstrap(archive, bootstrap, dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
