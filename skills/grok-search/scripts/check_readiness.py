#!/usr/bin/env python3
"""Grok-search plugin readiness probe.

Interface: probe(environ) -> {status, reasons, url, migrated, warnings}.
Does not write ~/.cursor/mcp.json, config.toml, or mcp.env.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Mapping

PRODUCTION_MCP_URL = "https://search.karldigi.dev/mcp"
URL_ENV = "GROK_SEARCH_MCP_URL"
TOKEN_ENV = "GROK_SEARCH_MCP_TOKEN"
HEADLESS_OAUTH_LOOPBACK_WARNING = (
    "headless_oauth_loopback: SSH is a hint that the operator browser may not "
    "be this host. MCP OAuth loopback (localhost callback) binds on this host, "
    "so a browser on another machine cannot finish it. Grok: overlay a bearer "
    "in ~/.grok/config.toml [mcp_servers.grok-search] url = "
    f'"{PRODUCTION_MCP_URL}" plus [mcp_servers.grok-search.headers] '
    f'Authorization = "Bearer ${{{TOKEN_ENV}}}"; Grok skips OAuth when that '
    "header is set. Cursor CLI: cursor-cli-mcp.example.json. Process env "
    "token alone does not skip plugin OAuth. Do not click the grok-search "
    "OAuth login on another machine. This probe never writes config.toml."
)
LEFTOVER_STDIO_CONFIG_WARNING = (
    "leftover_stdio_config: ~/.grok/config.toml [mcp_servers.grok-search] is "
    "stdio (command=) and shadows the marketplace HTTP plugin. Grok /mcps i "
    "auth is HTTP/SSE only. Remove that table, or replace command= with the "
    "HTTP url overlay. This probe never writes config.toml."
)
GROK_CONFIG_RELATIVE = (".grok", "config.toml")
STDIO_TABLE = "mcp_servers.grok-search"
# Dead preview listeners. Warn only — never live-probe, never fail the session.
STALE_PREVIEW_HOSTS = frozenset({"100.76.134.104"})
STALE_PREVIEW_HOST_PORTS = frozenset({("100.118.12.90", 8800)})


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


def _leftover_stdio_grok_search(config_text: str) -> bool:
    """True when [mcp_servers.grok-search] sets command= (stdio), not url=."""
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
    if _leftover_stdio_grok_search(text):
        return LEFTOVER_STDIO_CONFIG_WARNING
    return None


def _stale_preview_warning(url: str) -> str | None:
    """Return a warning if URL points at a retired Tailscale/sg01 :8800 preview."""
    from urllib.parse import urlparse

    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if not host:
        return None
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80
    if host in STALE_PREVIEW_HOSTS or (host, port) in STALE_PREVIEW_HOST_PORTS:
        return (
            f"{URL_ENV} points at stale grok-search preview {host}:{port}; "
            f"kr01 production is {PRODUCTION_MCP_URL}. Do not start sg01 :8800."
        )
    return None


def probe(environ: Mapping[str, str] | None = None) -> dict:
    source = os.environ if environ is None else environ
    url = _strip(source.get(URL_ENV))
    migrated = False
    warnings: list[str] = []
    reasons: list[str] = []

    if not url:
        url = PRODUCTION_MCP_URL
        migrated = True
        reasons.append(f"{URL_ENV} empty; using {PRODUCTION_MCP_URL}")

    stale = _stale_preview_warning(url)
    if stale:
        warnings.append(stale)

    leftover = _leftover_stdio_warning(source)
    if leftover:
        warnings.append(leftover)

    if _ssh_remote_session(source):
        warnings.append(HEADLESS_OAUTH_LOOPBACK_WARNING)

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
    if not url:
        return result
    target[URL_ENV] = url
    env_file = _strip(target.get("CLAUDE_ENV_FILE"))
    if env_file:
        with open(env_file, "a", encoding="utf-8") as handle:
            handle.write(f"export {URL_ENV}={url}\n")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="grok-search readiness probe")
    parser.add_argument("--json", action="store_true", help="print JSON verdict")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="set GROK_SEARCH_MCP_URL in this child process and Claude's CLAUDE_ENV_FILE",
    )
    args = parser.parse_args(argv)
    result = apply() if args.apply else probe()
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result["status"] == "in_sync" else 2


if __name__ == "__main__":
    sys.exit(main())
