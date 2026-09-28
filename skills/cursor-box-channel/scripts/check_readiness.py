#!/usr/bin/env python3
"""cursor-box-channel HTTP MCP plugin readiness probe.

Interface: probe(environ) -> {status, reasons, url, migrated, warnings}.
Does not write ~/.cursor/mcp.json, config.toml, or mcp.env.
Never prints CURSOR_BOX_MCP_TOKEN.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Mapping

PRODUCTION_MCP_URL = "https://channel.termolo.com/mcp"
TOKEN_ENV = "CURSOR_BOX_MCP_TOKEN"
URL_ENV = "CURSOR_BOX_MCP_URL"
HEADLESS_OAUTH_LOOPBACK_WARNING = (
    "headless_oauth_loopback: SSH is a hint that the operator browser may not "
    "be this host. MCP OAuth loopback (localhost callback) binds on this host, "
    "so a browser on another machine cannot finish it. Installed plugin "
    f".mcp.json sends Authorization Bearer ${{{TOKEN_ENV}}}; export that env. "
    "Missing token yields 401. Do not click a cursor-box-channel OAuth login "
    "on another machine. This probe never writes config.toml."
)
LEFTOVER_STDIO_CONFIG_WARNING = (
    "leftover_stdio_config: ~/.grok/config.toml "
    "[mcp_servers.cursor-box-channel] is stdio (command=) and shadows the "
    "marketplace HTTP plugin. Grok /mcps i auth is HTTP/SSE only. Remove that "
    "table, or replace command= with the HTTP url overlay. This probe never "
    "writes config.toml."
)
GROK_CONFIG_RELATIVE = (".grok", "config.toml")
STDIO_TABLE = "mcp_servers.cursor-box-channel"


def _strip(value: str | None) -> str:
    return (value or "").strip()


def _ssh_remote_session(source: Mapping[str, str]) -> bool:
    """SSH hint that the operator browser may not be this host (loopback binds here)."""
    return bool(_strip(source.get("SSH_CONNECTION")) or _strip(source.get("SSH_TTY")))


def _grok_config_path(source: Mapping[str, str]) -> str | None:
    home = _strip(source.get("HOME"))
    if not home:
        return None
    return os.path.join(home, *GROK_CONFIG_RELATIVE)


def _leftover_stdio_table(config_text: str) -> bool:
    """True when [mcp_servers.cursor-box-channel] sets command= (stdio), not url=."""
    in_table = False
    for raw in config_text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_table = stripped[1:-1] == STDIO_TABLE
            continue
        if not in_table or not stripped or stripped.startswith("#"):
            continue
        key = stripped.split("=", 1)[0].strip()
        if key == "command":
            return True
    return False


def _leftover_stdio_warning(source: Mapping[str, str]) -> str | None:
    path = _grok_config_path(source)
    if not path:
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        return None
    if _leftover_stdio_table(text):
        return LEFTOVER_STDIO_CONFIG_WARNING
    return None


def probe(environ: Mapping[str, str] | None = None) -> dict:
    source = os.environ if environ is None else environ
    token = _strip(source.get(TOKEN_ENV))
    url = _strip(source.get(URL_ENV))
    warnings: list[str] = []
    reasons: list[str] = []

    leftover = _leftover_stdio_warning(source)
    if leftover:
        warnings.append(leftover)

    if not token:
        if _ssh_remote_session(source):
            warnings.append(HEADLESS_OAUTH_LOOPBACK_WARNING)
        return {
            "status": "missing_prereq",
            "reasons": [f"{TOKEN_ENV} unset"],
            "url": url or None,
            "migrated": False,
            "warnings": warnings,
        }

    migrated = False
    if not url:
        url = PRODUCTION_MCP_URL
        migrated = True
        reasons.append(f"{URL_ENV} empty; using {PRODUCTION_MCP_URL}")

    return {
        "status": "in_sync",
        "reasons": reasons,
        "url": url,
        "migrated": migrated,
        "warnings": warnings,
    }


def apply(environ: dict[str, str] | None = None) -> dict:
    """Apply the URL default to this process and Claude's env handoff only."""
    target = os.environ if environ is None else environ
    result = probe(target)
    if result["status"] != "in_sync" or not result.get("migrated"):
        return result
    url = result["url"]
    target[URL_ENV] = url
    env_file = _strip(target.get("CLAUDE_ENV_FILE"))
    if env_file:
        with open(env_file, "a", encoding="utf-8") as handle:
            handle.write(f"export {URL_ENV}={url}\n")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="cursor-box-channel HTTP MCP readiness probe"
    )
    parser.add_argument("--json", action="store_true", help="print JSON verdict")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="set CURSOR_BOX_MCP_URL in this child process and Claude's CLAUDE_ENV_FILE when TOKEN is set",
    )
    args = parser.parse_args(argv)
    result = apply() if args.apply else probe()
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result["status"] == "in_sync" else 2


if __name__ == "__main__":
    sys.exit(main())
