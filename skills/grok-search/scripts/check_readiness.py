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
TOKEN_ENV = "GROK_SEARCH_MCP_TOKEN"
URL_ENV = "GROK_SEARCH_MCP_URL"
# Dead preview listeners. Warn only — never live-probe, never fail the session.
STALE_PREVIEW_HOSTS = frozenset({"100.76.134.104"})
STALE_PREVIEW_HOST_PORTS = frozenset({("100.118.12.90", 8800)})


def _strip(value: str | None) -> str:
    return (value or "").strip()


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
    token = _strip(source.get(TOKEN_ENV))
    url = _strip(source.get(URL_ENV))
    migrated = False
    warnings: list[str] = []
    reasons: list[str] = []

    if not token:
        return {
            "status": "missing_prereq",
            "reasons": [f"{TOKEN_ENV} unset"],
            "url": url or None,
            "migrated": False,
            "warnings": warnings,
        }

    if not url:
        url = PRODUCTION_MCP_URL
        migrated = True
        reasons.append(f"{URL_ENV} empty; using {PRODUCTION_MCP_URL}")

    stale = _stale_preview_warning(url)
    if stale:
        warnings.append(stale)

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
        help="set GROK_SEARCH_MCP_URL in this child process and Claude's CLAUDE_ENV_FILE when TOKEN is set",
    )
    args = parser.parse_args(argv)
    result = apply() if args.apply else probe()
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result["status"] == "in_sync" else 2


if __name__ == "__main__":
    sys.exit(main())
