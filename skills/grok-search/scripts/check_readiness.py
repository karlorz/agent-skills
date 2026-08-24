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


def _strip(value: str | None) -> str:
    return (value or "").strip()


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

    return {
        "status": "in_sync",
        "reasons": reasons,
        "url": url,
        "migrated": migrated,
        "warnings": warnings,
    }


def apply(environ: dict[str, str] | None = None) -> dict:
    """Apply URL default into process env and optional CLAUDE_ENV_FILE."""
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
            handle.write(f"{URL_ENV}={url}\n")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="grok-search readiness probe")
    parser.add_argument("--json", action="store_true", help="print JSON verdict")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="set GROK_SEARCH_MCP_URL in this process / CLAUDE_ENV_FILE when TOKEN is set",
    )
    args = parser.parse_args(argv)
    result = apply() if args.apply else probe()
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result["status"] == "in_sync" else 2


if __name__ == "__main__":
    sys.exit(main())
