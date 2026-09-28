#!/usr/bin/env bash
# Behaviour tests for cursor-box-channel readiness probe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$ROOT/skills/cursor-box-channel/scripts/check_readiness.py"

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
production_url = "https://channel.termolo.com/mcp"


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
    return payload, proc.returncode


def base_env():
    return {
        "PATH": os.environ.get("PATH", ""),
        "HOME": os.environ.get("HOME", "/tmp"),
        "LANG": "C",
    }


# Missing token: missing_prereq, no loopback warning off SSH
out, rc = run(base_env())
if rc != 2:
    raise SystemExit(f"missing token exit={rc}, want 2")
if out.get("status") != "missing_prereq":
    raise SystemExit(f"missing token status={out!r}, want missing_prereq")
if "CURSOR_BOX_MCP_TOKEN unset" not in " ".join(out.get("reasons") or []):
    raise SystemExit(f"missing token must name CURSOR_BOX_MCP_TOKEN unset: {out!r}")
warns = " ".join(out.get("warnings") or [])
if "headless_oauth_loopback" in warns:
    raise SystemExit(f"non-SSH missing token must not warn headless_oauth_loopback: {out!r}")


# SSH + missing token warns operator-browser loopback
env = base_env()
env["SSH_CONNECTION"] = "1.2.3.4 12345 5.6.7.8 22"
out, rc = run(env)
if rc != 2 or out.get("status") != "missing_prereq":
    raise SystemExit(f"SSH missing token status={out!r} rc={rc}")
warns = " ".join(out.get("warnings") or [])
if "headless_oauth_loopback" not in warns:
    raise SystemExit(f"SSH missing token must warn headless_oauth_loopback: {out!r}")
if "CURSOR_BOX_MCP_TOKEN" not in warns:
    raise SystemExit(f"SSH warning must name CURSOR_BOX_MCP_TOKEN: {out!r}")
if "operator browser" not in warns.lower() or "this host" not in warns.lower():
    raise SystemExit(f"SSH warning must frame operator browser vs this-host: {out!r}")
if "hint" not in warns.lower():
    raise SystemExit(f"SSH warning must call SSH a hint: {out!r}")
if "config.toml" not in warns:
    raise SystemExit(f"SSH warning must say probe never writes config.toml: {out!r}")
for forbidden in ("DISPLAY", "headed", "auto-detect"):
    if forbidden in warns:
        raise SystemExit(f"SSH warning must not suggest headed auto-detect ({forbidden!r}): {out!r}")


# Token present: in_sync, default URL, never print token
token = "test-token-must-not-appear-in-output"
env = base_env()
env["CURSOR_BOX_MCP_TOKEN"] = token
out, rc = run(env)
if rc != 0 or out.get("status") != "in_sync":
    raise SystemExit(f"token-present status={out!r} rc={rc}")
if out.get("migrated") is not True:
    raise SystemExit(f"token-present must migrate empty URL: {out!r}")
if out.get("url") != production_url:
    raise SystemExit(f"default url={out.get('url')!r}")
if token in json.dumps(out):
    raise SystemExit("probe leaked token")
if "headless_oauth_loopback" in " ".join(out.get("warnings") or []):
    raise SystemExit(f"non-SSH token must not warn loopback: {out!r}")


# SSH + token: in_sync, no loopback warning
env = base_env()
env["CURSOR_BOX_MCP_TOKEN"] = token
env["SSH_TTY"] = "/dev/pts/0"
out, rc = run(env)
if rc != 0 or out.get("status") != "in_sync":
    raise SystemExit(f"SSH+token status={out!r} rc={rc}")
if "headless_oauth_loopback" in " ".join(out.get("warnings") or []):
    raise SystemExit(f"SSH with token must not warn headless_oauth_loopback: {out!r}")
if token in json.dumps(out):
    raise SystemExit("SSH+token probe leaked token")


# Explicit URL wins
env = base_env()
env["CURSOR_BOX_MCP_TOKEN"] = token
env["CURSOR_BOX_MCP_URL"] = "https://example.invalid/mcp"
out, rc = run(env)
if out.get("migrated") is True:
    raise SystemExit("explicit URL must not migrate")
if out.get("url") != "https://example.invalid/mcp":
    raise SystemExit(f"explicit url lost: {out!r}")


# Leftover stdio command= warns; --apply does not rewrite config.toml
with tempfile.TemporaryDirectory() as td:
    td_path = Path(td)
    grok_dir = td_path / ".grok"
    grok_dir.mkdir(parents=True)
    grok_config = grok_dir / "config.toml"
    grok_config.write_text(
        "[mcp_servers.cursor-box-channel]\n"
        'command = "uvx"\n'
        "[mcp_servers.cursor-box-channel.env]\n"
        'CURSOR_BOX_MCP_TOKEN = "must-not-appear"\n',
        encoding="utf-8",
    )
    before = grok_config.read_bytes()
    env = base_env()
    env["HOME"] = str(td_path)
    env["CURSOR_BOX_MCP_TOKEN"] = token
    out, rc = run(env, extra_args=["--apply"])
    if rc != 0 or out.get("status") != "in_sync":
        raise SystemExit(f"stdio leftover status={out!r} rc={rc}")
    warns = " ".join(out.get("warnings") or [])
    if "leftover_stdio_config" not in warns:
        raise SystemExit(f"stdio leftover must warn leftover_stdio_config: {out!r}")
    if "must-not-appear" in json.dumps(out) or "must-not-appear" in warns:
        raise SystemExit("probe leaked leftover stdio env value")
    if grok_config.read_bytes() != before:
        raise SystemExit("probe must not write leftover stdio config.toml")


# HTTP url table is not leftover stdio
with tempfile.TemporaryDirectory() as td:
    td_path = Path(td)
    grok_dir = td_path / ".grok"
    grok_dir.mkdir(parents=True)
    (grok_dir / "config.toml").write_text(
        "[mcp_servers.cursor-box-channel]\n"
        f'url = "{production_url}"\n'
        "\n"
        "[mcp_servers.cursor-box-channel.headers]\n"
        'Authorization = "Bearer ${CURSOR_BOX_MCP_TOKEN}"\n',
        encoding="utf-8",
    )
    env = base_env()
    env["HOME"] = str(td_path)
    env["CURSOR_BOX_MCP_TOKEN"] = token
    out, _rc = run(env)
    warns = " ".join(out.get("warnings") or [])
    if "leftover_stdio_config" in warns:
        raise SystemExit(f"HTTP url table must not warn leftover_stdio_config: {out!r}")


# --apply writes URL into CLAUDE_ENV_FILE when token is set; never mcp.json / mcp.env / config.toml
with tempfile.TemporaryDirectory() as td:
    td_path = Path(td)
    env_file = td_path / "claude.env"
    mcp_json = td_path / "mcp.json"
    mcp_env = td_path / "mcp.env"
    grok_dir = td_path / ".grok"
    grok_dir.mkdir(parents=True)
    grok_config = grok_dir / "config.toml"
    mcp_json.write_text("{}\n", encoding="utf-8")
    mcp_env.write_text("CURSOR_BOX_MCP_TOKEN=keep\n", encoding="utf-8")
    grok_config.write_text("[plugins]\nenabled = []\n", encoding="utf-8")
    before_toml = grok_config.read_bytes()
    env = base_env()
    env["HOME"] = str(td_path)
    env["CLAUDE_ENV_FILE"] = str(env_file)
    env["CURSOR_BOX_MCP_TOKEN"] = token
    out, rc = run(env, extra_args=["--apply"])
    if rc != 0 or out.get("migrated") is not True:
        raise SystemExit(f"--apply should migrate: {out!r} rc={rc}")
    written = env_file.read_text(encoding="utf-8")
    if written != f"export CURSOR_BOX_MCP_URL={production_url}\n":
        raise SystemExit(f"CLAUDE_ENV_FILE missing exact URL export line:\n{written!r}")
    if mcp_json.read_text(encoding="utf-8") != "{}\n":
        raise SystemExit("must not write mcp.json")
    if mcp_env.read_text(encoding="utf-8") != "CURSOR_BOX_MCP_TOKEN=keep\n":
        raise SystemExit("must not write mcp.env")
    if grok_config.read_bytes() != before_toml:
        raise SystemExit("must not write config.toml")
    if token in written:
        raise SystemExit("CLAUDE_ENV_FILE leaked token")


print("test-cursor-box-channel-readiness: all checks passed")
PY
