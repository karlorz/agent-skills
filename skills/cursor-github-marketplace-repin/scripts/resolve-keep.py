#!/usr/bin/env python3
"""Resolve KEEP plugin specs: keep.default.json ∪ extra − drop."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_HOME_LOCAL = Path(".cursor/skills/cursor-github-marketplace-repin/keep.local.json")


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path, label: str) -> object:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"{label} unreadable ({path}): {exc}")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"{label} is not JSON ({path}): {exc}")


def require_spec_list(value: object, label: str) -> list[str]:
    if not isinstance(value, list):
        fail(f"{label} must be an array of name@marketplace strings")
    out: list[str] = []
    for item in value:
        if not isinstance(item, str) or item.count("@") != 1:
            fail(f"bad KEEP spec {item!r} in {label}")
        name, _, marketplace = item.partition("@")
        if not name or not marketplace:
            fail(f"bad KEEP spec {item!r} in {label}")
        out.append(item)
    return out


def default_path() -> Path:
    override = os.environ.get("CURSOR_REPIN_KEEP_DEFAULT", "").strip()
    return Path(override) if override else SCRIPT_DIR / "keep.default.json"


def local_path() -> Path | None:
    if "CURSOR_REPIN_KEEP_FILE" in os.environ:
        override = os.environ["CURSOR_REPIN_KEEP_FILE"].strip()
        if not override:
            return None
        return Path(override)
    return Path.home() / DEFAULT_HOME_LOCAL


def load_default(path: Path) -> list[str]:
    if not path.is_file():
        fail(f"keep.default.json missing ({path})")
    data = load_json(path, "keep.default.json")
    if not isinstance(data, dict):
        fail("keep.default.json must be an object with specs")
    return require_spec_list(data.get("specs"), "keep.default.json specs")


def load_local(path: Path | None) -> tuple[list[str], list[str]]:
    if path is None:
        return [], []
    explicit = bool(os.environ.get("CURSOR_REPIN_KEEP_FILE", "").strip())
    if not path.is_file():
        if explicit:
            fail(f"CURSOR_REPIN_KEEP_FILE missing ({path})")
        return [], []
    data = load_json(path, "keep.local.json")
    if not isinstance(data, dict):
        fail("keep.local.json must be an object with extra and/or drop")
    extra = require_spec_list(data.get("extra", []), "keep.local.json extra")
    drop = require_spec_list(data.get("drop", []), "keep.local.json drop")
    return extra, drop


def merge(default: list[str], extra: list[str], drop: list[str]) -> list[str]:
    ordered: list[str] = []
    seen: set[str] = set()
    for spec in default + extra:
        if spec in seen:
            continue
        seen.add(spec)
        ordered.append(spec)
    drop_set = set(drop)
    unknown_drop = sorted(drop_set - seen)
    if unknown_drop:
        fail("drop names a spec not in default ∪ extra: " + ", ".join(unknown_drop))
    return [spec for spec in ordered if spec not in drop_set]


def main() -> None:
    specs = merge(load_default(default_path()), *load_local(local_path()))
    for spec in specs:
        print(spec)


if __name__ == "__main__":
    main()
