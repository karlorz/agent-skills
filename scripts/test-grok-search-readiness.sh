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


# Missing token → missing_prereq, no URL default
out = run(base_env())
if out.get("status") != "missing_prereq":
    raise SystemExit(f"empty env status={out!r}, want missing_prereq")
if out.get("migrated") is True:
    raise SystemExit("empty env must not migrate URL")
if "GROK_SEARCH_MCP_TOKEN" not in " ".join(out.get("reasons") or []):
    raise SystemExit(f"reasons must mention TOKEN: {out!r}")


# Token set, URL empty → in_sync + migrated default production URL
env = base_env()
env["GROK_SEARCH_MCP_TOKEN"] = "test-token-not-a-secret"
out = run(env)
if out.get("status") != "in_sync":
    raise SystemExit(f"token-only status={out!r}, want in_sync")
if out.get("migrated") is not True:
    raise SystemExit(f"token-only must set migrated: {out!r}")
if out.get("url") != "https://search.karldigi.dev/mcp":
    raise SystemExit(f"default url={out.get('url')!r}")


# Explicit URL wins; no migrate
env = base_env()
env["GROK_SEARCH_MCP_TOKEN"] = "test-token-not-a-secret"
env["GROK_SEARCH_MCP_URL"] = "http://127.0.0.1:8800/mcp"
out = run(env)
if out.get("status") != "in_sync":
    raise SystemExit(f"explicit url status={out!r}")
if out.get("migrated") is True:
    raise SystemExit("explicit URL must not migrate")
if out.get("url") != "http://127.0.0.1:8800/mcp":
    raise SystemExit(f"explicit url lost: {out!r}")


# --apply writes URL into CLAUDE_ENV_FILE, never mcp.json / mcp.env
with tempfile.TemporaryDirectory() as td:
    td_path = Path(td)
    env_file = td_path / "claude.env"
    mcp_json = td_path / "mcp.json"
    mcp_env = td_path / "mcp.env"
    mcp_json.write_text("{}\n", encoding="utf-8")
    mcp_env.write_text("GROK_SEARCH_MCP_TOKEN=keep\n", encoding="utf-8")
    env = base_env()
    env["GROK_SEARCH_MCP_TOKEN"] = "test-token-not-a-secret"
    env["CLAUDE_ENV_FILE"] = str(env_file)
    env["HOME"] = str(td_path)
    out = run(env, extra_args=["--apply"])
    if out.get("migrated") is not True:
        raise SystemExit(f"--apply should migrate: {out!r}")
    written = env_file.read_text(encoding="utf-8")
    if "GROK_SEARCH_MCP_URL=https://search.karldigi.dev/mcp" not in written:
        raise SystemExit(f"CLAUDE_ENV_FILE missing URL export:\n{written}")
    if "test-token" in written:
        raise SystemExit("CLAUDE_ENV_FILE leaked token")
    if mcp_json.read_text(encoding="utf-8") != "{}\n":
        raise SystemExit("must not write mcp.json")
    if mcp_env.read_text(encoding="utf-8") != "GROK_SEARCH_MCP_TOKEN=keep\n":
        raise SystemExit("must not write mcp.env")


# stdout JSON must never contain the raw token
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
