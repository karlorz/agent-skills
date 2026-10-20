#!/usr/bin/env python3
"""Install a staged config.toml into the live grok home safely.

Config files carry host state (skill exclusions, plugin paths, inline keys), so
a plain copy can silently discard changes another writer made after the render.
This helper replaces that copy with a staged, validated, atomic install:

  1. read the staged source and require it to parse as TOML;
  2. acquire a sibling advisory lock, re-read the destination, and compare its
     SHA-256 with --expected-sha256 (the hash the caller rendered against);
     a mismatch is a stale-write conflict and aborts with exit 3;
  3. copy the destination to --backup-dir when it differs;
  4. write a temp file in the destination directory, fsync it, chmod it to the
     destination mode, and os.replace() it into place (atomic on one filesystem);
  5. fsync the directory so the rename survives a crash.

Symlinks: a symlinked config.toml is written *through* — the link itself is
kept and the resolved target is replaced. Permissions of an existing
destination are preserved; a new file keeps the staged source mode.

Concurrency guarantee is bounded: cooperating installers serialize on the lock
file, and a stale snapshot is always rejected. A writer that ignores both the
lock and the hash check (an editor, a GUI config app) is outside the guarantee
and can still race between the final check and the rename.

Exit codes: 0 installed or identical, 1 invalid source / IO error,
2 no TOML parser, 3 stale-hash conflict.

Machine-readable stdout lines: `identical`, `installed`, `backup <path>`,
`target <path>` (symlink resolution). Nothing secret is printed.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import os
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path

ABSENT = "absent"


class InstallError(Exception):
    """Install cannot proceed; the destination is untouched."""


class ParserUnavailable(InstallError):
    """No TOML parser in this interpreter, so the staged file cannot be checked."""


class StaleWrite(InstallError):
    """Destination changed since the caller rendered against it."""


def toml_module():
    try:
        import tomllib  # Python 3.11+
    except ModuleNotFoundError:
        try:
            import tomli  # pip install tomli on older Pythons
        except ModuleNotFoundError as exc:
            raise ParserUnavailable(
                "no TOML parser available (need Python 3.11+ tomllib or tomli)"
            ) from exc
        return tomli
    return tomllib


def validate_source(path: Path) -> bytes:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise InstallError(f"cannot read staged config {path}: {exc}") from exc
    if not data.strip():
        raise InstallError(f"staged config {path} is empty")
    module = toml_module()
    try:
        parsed = module.loads(data.decode("utf-8"))
    except Exception as exc:
        raise InstallError(f"staged config {path} is not valid TOML: {exc}") from exc
    if not isinstance(parsed, dict) or not parsed:
        raise InstallError(f"staged config {path} does not parse to a table")
    return data


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hash_path(path: Path) -> str:
    if not path.exists():
        return ABSENT
    return sha256_bytes(path.read_bytes())


def destination_target(dest: Path) -> Path:
    """Resolve a symlinked destination so the link survives the write."""
    if not dest.is_symlink():
        return dest
    target = Path(os.path.realpath(dest))
    if not target.exists():
        raise InstallError(f"{dest} is a symlink to missing {target}")
    print(f"target {target}")
    return target


@contextlib.contextmanager
def _lock_file(dest: Path):
    """Return a context manager holding an advisory lock beside `dest`.

    The lock file stays behind on purpose: unlinking a flock target lets two
    waiters lock different inodes, which would defeat the lock entirely.
    """
    lock_path = dest.with_name("." + dest.name + ".lock")
    try:
        fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError as exc:
        raise InstallError(
            f"cannot open lock file {lock_path}: {exc} (does {dest.parent} exist?)"
        ) from exc
    try:
        if sys.platform == "win32":  # pragma: no cover - exercised on Windows
            import msvcrt

            msvcrt.locking(fd, msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


def _fsync_dir(path: Path) -> None:
    if sys.platform == "win32":  # pragma: no cover - directory fsync is POSIX-only
        return
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def install(
    source: Path,
    dest: Path,
    expected: str | None,
    backup_dir: Path | None,
) -> int:
    data = validate_source(source)
    new_hash = sha256_bytes(data)
    dest.parent.mkdir(parents=True, exist_ok=True)
    target = destination_target(dest)

    with _lock_file(target):
        current = hash_path(target)
        if expected is not None and current != expected:
            raise StaleWrite(
                f"{dest} changed since the render (expected {expected}, found {current})"
            )
        if current == new_hash:
            print("identical")
            return 0
        if current != ABSENT:
            if backup_dir is not None:
                backup_dir.mkdir(parents=True, exist_ok=True)
                backup = backup_dir / target.name
                shutil.copy2(target, backup)
                print(f"backup {backup}")
            mode = stat.S_IMODE(target.stat().st_mode)
        else:
            mode = stat.S_IMODE(source.stat().st_mode)

        fd, tmp_name = tempfile.mkstemp(
            prefix=f".{target.name}.", suffix=".tmp", dir=str(target.parent)
        )
        tmp = Path(tmp_name)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(tmp, mode)
            os.replace(tmp, target)
        except OSError as exc:
            with contextlib.suppress(OSError):
                tmp.unlink()
            raise InstallError(f"cannot replace {target}: {exc}") from exc
        _fsync_dir(target.parent)
        print("installed")
        return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path,
                        help="staged config.toml rendered by generate-config.py")
    parser.add_argument("--dest", type=Path,
                        help="live config.toml to replace")
    parser.add_argument("--expected-sha256", default=None,
                        help='hash of the destination the render was based on; '
                             '"absent" means the file must not exist yet')
    parser.add_argument("--backup-dir", type=Path, default=None,
                        help="directory that receives the previous destination")
    parser.add_argument("--hash", type=Path, default=None,
                        help="print the SHA-256 of PATH (or 'absent') and exit")
    args = parser.parse_args(argv)

    if args.hash is not None:
        try:
            print(hash_path(args.hash))
        except OSError as exc:
            print(f"install-config: ERROR: cannot hash {args.hash}: {exc}", file=sys.stderr)
            return 1
        return 0

    if args.source is None or args.dest is None:
        parser.error("--source and --dest are required unless --hash is used")

    if args.expected_sha256 is not None:
        expected = args.expected_sha256.strip().lower()
        if expected != ABSENT and re.fullmatch(r"[0-9a-f]{64}", expected) is None:
            print("install-config: ERROR: --expected-sha256 requires 64 hex characters or 'absent'", file=sys.stderr)
            return 1
    else:
        expected = None

    try:
        return install(args.source, args.dest, expected, args.backup_dir)
    except StaleWrite as exc:
        print(f"install-config: ERROR: stale write rejected: {exc}", file=sys.stderr)
        print("install-config: re-run the installer to render against the current file",
              file=sys.stderr)
        return 3
    except ParserUnavailable as exc:
        print(f"install-config: ERROR: {exc}; {args.dest} left unchanged", file=sys.stderr)
        return 2
    except (InstallError, OSError) as exc:
        print(f"install-config: ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
