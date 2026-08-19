#!/usr/bin/env python3
"""Migrate an existing user grok-search MCP install onto the plugin env file.

Never prints secret values. Default is dry-run.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

CARRY_KEYS = ("GUDA_API_KEY", "GUDA_BASE_URL", "GROK_MODEL")
ENV_FILE = Path.home() / ".config" / "grok-search" / "mcp.env"


def _load_json(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _grok_search_env(servers: object) -> dict[str, str] | None:
    if not isinstance(servers, dict):
        return None
    cfg = servers.get("grok-search")
    if not isinstance(cfg, dict):
        return None
    env = cfg.get("env")
    if not isinstance(env, dict):
        return {}
    out: dict[str, str] = {}
    for key, value in env.items():
        if isinstance(key, str) and isinstance(value, str):
            out[key] = value
    return out


def discover(home: Path) -> list[tuple[str, Path, dict[str, str]]]:
    found: list[tuple[str, Path, dict[str, str]]] = []
    claude = home / ".claude.json"
    data = _load_json(claude)
    if data:
        env = _grok_search_env(data.get("mcpServers"))
        if env is not None:
            found.append(("claude-user", claude, env))
    cursor = home / ".cursor" / "mcp.json"
    data = _load_json(cursor)
    if data:
        env = _grok_search_env(data.get("mcpServers") or data)
        if env is not None:
            found.append(("cursor-user", cursor, env))
    return found


def write_env_file(env: dict[str, str], dest: Path) -> list[str]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    carried = []
    for key in CARRY_KEYS:
        value = env.get(key, "")
        if not value:
            continue
        lines.append(f"{key}={value}\n")
        carried.append(key)
    dest.write_text("".join(lines), encoding="utf-8")
    os.chmod(dest, stat.S_IRUSR | stat.S_IWUSR)
    return carried


def remove_cursor_entry(path: Path) -> None:
    backup = path.with_suffix(path.suffix + ".bak-grok-search-migrate")
    shutil.copy2(path, backup)
    data = json.loads(path.read_text(encoding="utf-8"))
    servers = data.get("mcpServers")
    if isinstance(servers, dict) and "grok-search" in servers:
        del servers["grok-search"]
        data["mcpServers"] = servers
    elif isinstance(data, dict) and "grok-search" in data and "mcpServers" not in data:
        del data["grok-search"]
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply-env", action="store_true", help="Write ~/.config/grok-search/mcp.env")
    parser.add_argument("--remove-user-mcp", action="store_true", help="Remove user grok-search after env file exists")
    parser.add_argument("--home", type=Path, default=Path.home(), help=argparse.SUPPRESS)
    args = parser.parse_args()

    found = discover(args.home)
    if not found:
        print("migrate-from-user-mcp: no user grok-search MCP found")
        return 0

    merged: dict[str, str] = {}
    for scope, path, env in found:
        keys = [k for k in CARRY_KEYS if env.get(k)]
        extra = sorted(set(env) - set(CARRY_KEYS))
        print(f"found {scope} at {path} keys={keys} extra_keys={extra}")
        for key in CARRY_KEYS:
            if key in env and key not in merged:
                merged[key] = env[key]

    dest = args.home / ".config" / "grok-search" / "mcp.env" if args.home != Path.home() else ENV_FILE
    if not args.apply_env:
        print(f"dry-run: would write keys {list(merged)} to {dest} (mode 600)")
        if args.remove_user_mcp:
            print("dry-run: would then remove user grok-search from Claude (-s user) and Cursor mcp.json")
        return 0

    carried = write_env_file(merged, dest)
    print(f"wrote {dest} keys={carried} mode=600")

    if not args.remove_user_mcp:
        print("env file written; pass --remove-user-mcp to drop the user MCP entries")
        return 0

    if dest == ENV_FILE:
        subprocess.run(["claude", "mcp", "remove", "grok-search", "-s", "user"], check=False)
    cursor = args.home / ".cursor" / "mcp.json"
    if cursor.is_file():
        remove_cursor_entry(cursor)
        print(f"removed grok-search from {cursor} (backup .bak-grok-search-migrate)")
    print("user grok-search MCP removed; restart Claude/Cursor so plugin MCP can attach")
    return 0


if __name__ == "__main__":
    sys.exit(main())
