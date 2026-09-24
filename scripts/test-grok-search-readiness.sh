#!/usr/bin/env bash
# Behaviour tests for grok-search readiness probe (TDD surface).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$ROOT/skills/grok-search/scripts/check_readiness.py"

if [[ ! -f "$PROBE" ]]; then
  printf 'missing probe: %s\n' "$PROBE" >&2
  exit 1
fi

python3 - "$PROBE" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

probe = Path(sys.argv[1])


def run(env, extra_args=None):
    cmd = [sys.executable, str(probe), "--json"]
    if extra_args:
        cmd.extend(extra_args)
    proc = subprocess.run(
        cmd,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"probe exit {proc.returncode} bad json: {exc}\nstdout={proc.stdout}\nstderr={proc.stderr}"
        ) from exc
    return payload


def base_env():
    return {
        "PATH": os.environ.get("PATH", ""),
        "HOME": os.environ.get("HOME", "/tmp"),
        "LANG": "C",
    }


# Empty environment is in_sync, migrated true, defaults to production URL, no token reason
out = run(base_env())
if out.get("status") != "in_sync":
    raise SystemExit(f"empty env status={out!r}, want in_sync")
if out.get("migrated") is not True:
    raise SystemExit("empty env must migrate URL to production default")
if out.get("url") != "https://search.karldigi.dev/mcp":
    raise SystemExit(f"empty env url={out.get('url')!r}, want https://search.karldigi.dev/mcp")
for reason in out.get("reasons") or []:
    if "TOKEN" in reason:
        raise SystemExit(f"empty env must not emit token reason: {reason!r}")


# Explicit URL wins; no migrate (no token required)
env = base_env()
env["GROK_SEARCH_MCP_URL"] = "http://127.0.0.1:8800/mcp"
out = run(env)
if out.get("status") != "in_sync":
    raise SystemExit(f"explicit url status={out!r}")
if out.get("migrated") is True:
    raise SystemExit("explicit URL must not migrate")
if out.get("url") != "http://127.0.0.1:8800/mcp":
    raise SystemExit(f"explicit url lost: {out!r}")
if out.get("warnings"):
    raise SystemExit(f"loopback 8800 is not a stale preview URL: {out!r}")


# Stale Tailscale preview IP — warn, stay in_sync, do not live-probe
env = base_env()
env["GROK_SEARCH_MCP_URL"] = "http://100.76.134.104:8800/mcp"
out = run(env)
if out.get("status") != "in_sync":
    raise SystemExit(f"stale tailscale must stay in_sync: {out!r}")
if out.get("migrated") is True:
    raise SystemExit("stale explicit URL must not migrate")
warns = " ".join(out.get("warnings") or [])
if "stale" not in warns.lower() or "100.76.134.104" not in warns:
    raise SystemExit(f"stale tailscale must warn: {out!r}")


# Current sg01 Tailscale + :8800 — same warning (no listener there)
env = base_env()
env["GROK_SEARCH_MCP_URL"] = "http://100.118.12.90:8800/mcp"
out = run(env)
if out.get("status") != "in_sync":
    raise SystemExit(f"sg01 :8800 must stay in_sync: {out!r}")
warns = " ".join(out.get("warnings") or [])
if "stale" not in warns.lower():
    raise SystemExit(f"sg01 :8800 must warn stale: {out!r}")


# Production explicit URL — no stale warning
env = base_env()
env["GROK_SEARCH_MCP_URL"] = "https://search.karldigi.dev/mcp"
out = run(env)
if out.get("warnings"):
    raise SystemExit(f"production URL must not warn stale: {out!r}")


# Token-present case: an optional environment token does not alter readiness or URL handling
env = base_env()
env["GROK_SEARCH_MCP_TOKEN"] = "test-token-not-a-secret"
out = run(env)
if out.get("status") != "in_sync":
    raise SystemExit(f"token-present status={out!r}, want in_sync")
if out.get("migrated") is not True:
    raise SystemExit(f"token-present must set migrated: {out!r}")
if out.get("url") != "https://search.karldigi.dev/mcp":
    raise SystemExit(f"default url={out.get('url')!r}")


# A token stored only in operator mcp.env is not process environment and must not be sourced.
# Empty environment is in_sync, defaults URL, and never modifies operator files.
with tempfile.TemporaryDirectory() as td:
    td_path = Path(td)
    config_dir = td_path / ".config" / "grok-search"
    cursor_dir = td_path / ".cursor"
    grok_dir = td_path / ".grok"
    config_dir.mkdir(parents=True)
    cursor_dir.mkdir(parents=True)
    grok_dir.mkdir(parents=True)
    mcp_env = config_dir / "mcp.env"
    cursor_mcp = cursor_dir / "mcp.json"
    grok_config = grok_dir / "config.toml"
    mcp_env.write_text("GROK_SEARCH_MCP_TOKEN=stored-token-not-process-env\n", encoding="utf-8")
    cursor_mcp.write_text('{"mcpServers":{"keep":{}}}\n', encoding="utf-8")
    grok_config.write_text("[plugins]\nenabled = []\n", encoding="utf-8")
    before = {path: path.read_bytes() for path in (mcp_env, cursor_mcp, grok_config)}
    env = base_env()
    env["HOME"] = str(td_path)
    out = run(env, extra_args=["--apply"])
    if out.get("status") != "in_sync":
        raise SystemExit(f"mcp.env-only token must remain in_sync: {out!r}")
    for path, expected in before.items():
        if path.read_bytes() != expected:
            raise SystemExit(f"probe modified operator file {path}")


# --apply writes URL into CLAUDE_ENV_FILE without requiring a token, never mcp.json / mcp.env
with tempfile.TemporaryDirectory() as td:
    td_path = Path(td)
    env_file = td_path / "claude.env"
    mcp_json = td_path / "mcp.json"
    mcp_env = td_path / "mcp.env"
    mcp_json.write_text("{}\n", encoding="utf-8")
    mcp_env.write_text("GROK_SEARCH_MCP_TOKEN=keep\n", encoding="utf-8")
    env = base_env()
    env["CLAUDE_ENV_FILE"] = str(env_file)
    env["HOME"] = str(td_path)
    out = run(env, extra_args=["--apply"])
    if out.get("migrated") is not True:
        raise SystemExit(f"--apply should migrate: {out!r}")
    written = env_file.read_text(encoding="utf-8")
    if written != "export GROK_SEARCH_MCP_URL=https://search.karldigi.dev/mcp\n":
        raise SystemExit(f"CLAUDE_ENV_FILE missing exact URL export line:\n{written!r}")
    if mcp_json.read_text(encoding="utf-8") != "{}\n":
        raise SystemExit("must not write mcp.json")
    if mcp_env.read_text(encoding="utf-8") != "GROK_SEARCH_MCP_TOKEN=keep\n":
        raise SystemExit("must not write mcp.env")


# stdout JSON must never contain the raw token when token is present
env = base_env()
env["GROK_SEARCH_MCP_TOKEN"] = "super-secret-token-value"
raw = subprocess.run(
    [sys.executable, str(probe), "--json"],
    env=env,
    capture_output=True,
    text=True,
    check=False,
)
if raw.returncode not in (0, 2):
    raise SystemExit(f"unexpected exit {raw.returncode}: {raw.stderr}")
if "super-secret-token-value" in raw.stdout or "super-secret-token-value" in raw.stderr:
    raise SystemExit("probe leaked token")

print("test-grok-search-readiness: all checks passed")
PY
