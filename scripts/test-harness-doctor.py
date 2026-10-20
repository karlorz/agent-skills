#!/usr/bin/env python3
"""Isolated fake-home tests for harness-doctor. Never touches the live home."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills" / "harness-doctor" / "scripts" / "harness-doctor.py"
PYTHON = sys.executable

SECRET_BEARER = "codex-secret-value-do-not-leak"
SECRET_KEY = "sk-live-secret-abcdef"
SECRET_EMAIL = "doctor-user@example.com"
SECRET_PROMPT = "SECRET_PROMPT_BODY_do_not_print"
AUTH_ID = "authid-should-never-appear"

PASS = 0
FAIL = 0


def fail(label: str, detail: str) -> None:
    global FAIL
    FAIL += 1
    print(f"FAIL: {label} — {detail}")


def ok(label: str) -> None:
    global PASS
    PASS += 1
    print(f"PASS: {label}")


def load_mod():
    spec = importlib.util.spec_from_file_location("harness_doctor", SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_json(path: Path, payload: object) -> None:
    write(path, json.dumps(payload, indent=2) + "\n")


def jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")


def touch_mtime(path: Path, days_ago: float) -> None:
    now = time.time()
    stamp = now - days_ago * 86400
    os.utime(path, (stamp, stamp))


def stub_bin(home: Path, name: str, script: str) -> Path:
    path = home / "bin" / name
    write(path, script)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def run_doctor(
    home: Path,
    args: list[str],
    path_dir: Path | None = None,
    env_extra: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["HARNESS_DOCTOR_SKIP_DETAILS"] = env.get("HARNESS_DOCTOR_SKIP_DETAILS", "0")
    env.pop("GROK_HOME", None)
    if env_extra:
        env.update(env_extra)
    if path_dir is not None:
        env["PATH"] = str(path_dir)
    else:
        env["PATH"] = str(home / "bin") + os.pathsep + env.get("PATH", "")
    return subprocess.run(
        [PYTHON, str(SCRIPT), "--home", str(home), *args],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )


def assert_no_secrets(blob: str, label: str) -> None:
    for secret in (SECRET_BEARER, SECRET_KEY, SECRET_EMAIL, SECRET_PROMPT, AUTH_ID, "Bearer secret-token"):
        if secret in blob:
            fail(label, f"leaked {secret!r}")
            return
    ok(label)


def iso_days_ago(days: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - days * 86400))


def make_claude_home(root: Path, *, sessions: int, span_days: float, extra: dict | None = None) -> None:
    extra = extra or {}
    plugin_usage = extra.get(
        "pluginUsage",
        {
            "used-plugin@demo": {"usageCount": 12, "lastUsedAt": 1_700_000_000_000, "lastUsedNumStartups": 10},
            "cold-plugin@demo": {"usageCount": 0, "lastUsedAt": 0, "lastUsedNumStartups": 0},
            "obsidian@obsidian-skills": {"usageCount": 0, "lastUsedAt": 0, "lastUsedNumStartups": 0},
            "cursor-github-marketplace-repin@demo": {
                "usageCount": 0,
                "lastUsedAt": 0,
                "lastUsedNumStartups": 0,
            },
        },
    )
    skill_usage = extra.get(
        "skillUsage",
        {
            "used-skill": {"usageCount": 4, "lastUsedAt": 1_700_000_000_000},
            "idle-skill": {"usageCount": 0, "lastUsedAt": 0},
        },
    )
    write_json(
        root / ".claude.json",
        {
            "installMethod": "global",
            "numStartups": 100,
            "firstStartTime": "2025-01-01T00:00:00.000Z",
            "pluginUsage": plugin_usage,
            "skillUsage": skill_usage,
            "projects": {
                "/tmp/demo": {
                    "lastSessionMetrics": {
                        "hook_duration_ms_count": 3,
                        "hook_duration_ms_avg": 20.0,
                        "hook_duration_ms_max": 40,
                    }
                }
            },
        },
    )
    write_json(
        root / ".claude" / "settings.json",
        {
            "enabledPlugins": {
                "used-plugin@demo": True,
                "cold-plugin@demo": True,
                "obsidian@obsidian-skills": True,
                "cursor-github-marketplace-repin@demo": True,
            },
            "permissions": {"defaultMode": "auto"},
        },
    )
    write_json(
        root / ".claude" / "plugins" / "installed_plugins.json",
        {"version": 2, "plugins": {"used-plugin@demo": [{"installPath": "/tmp/used"}]}},
    )
    memory = "Always reply in English.\n"
    write(root / ".claude" / "CLAUDE.md", memory)
    write(root / ".claude" / "rules" / "reply-in-english.md", memory)
    write(
        root / ".claude" / "plugins" / "cache" / "demo" / "used-plugin" / "1.0.0" / "skills" / "used" / "SKILL.md",
        "---\nname: used-skill\ndescription: used\n---\n",
    )
    proj = root / ".claude" / "projects" / "demo"
    for i in range(sessions):
        days_ago = 0 if sessions == 1 else span_days * i / max(sessions - 1, 1)
        ts = iso_days_ago(days_ago)
        rows = [
            {
                "type": "user",
                "timestamp": ts,
                "message": {"content": "/used-skill" if i == 0 else "hello"},
            },
            {
                "type": "assistant",
                "timestamp": ts,
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "name": "Skill",
                            "input": {"skill": "used-skill", "args": SECRET_PROMPT},
                        }
                    ]
                },
            },
            {
                "type": "system",
                "timestamp": ts,
                "hookEventName": "SessionStart" if i == 0 else "PreToolUse",
                "hookInfos": [
                    {
                        "event": "SessionStart" if i == 0 else "PreToolUse",
                        "durationMs": 2619 if i == 0 else 20,
                    }
                ],
            },
        ]
        if i < 3:
            rows.append(
                {
                    "type": "user",
                    "timestamp": ts,
                    "toolUseResult": {"denied": True, "command": "git status", "toolName": "Bash"},
                }
            )
        if i < 2:
            rows.append(
                {
                    "type": "user",
                    "timestamp": ts,
                    "toolUseResult": {"denied": True, "command": "git push", "toolName": "Bash"},
                }
            )
        path = proj / f"{i:04d}.jsonl"
        jsonl(path, rows)
        touch_mtime(path, days_ago)


def make_grok_home(root: Path, *, sessions: int, span_days: float) -> None:
    write(
        root / ".grok" / "config.toml",
        """
[plugins]
enabled = ["used-plugin", "cold-plugin"]

[mcp_servers.skillwiki]
url = "https://example.invalid/mcp?token=leak"

[mcp_servers.secret]
api_key = "sk-live-secret-abcdef"
""",
    )
    write(
        root / ".grok" / "AGENTS.md",
        "agent rules\n",
    )
    write(
        root / ".grok" / "bundled" / "skills" / "learn" / "collect_sessions.py",
        "print('should-not-run')\n",
    )
    write(
        root / ".grok" / "installed-plugins" / "used-plugin" / "skills" / "used-plugin" / "SKILL.md",
        "---\nname: used-plugin\ndescription: used grok plugin\n---\n",
    )
    write(
        root / ".grok" / "installed-plugins" / "cold-plugin" / "skills" / "cold-plugin" / "SKILL.md",
        "---\nname: cold-plugin\ndescription: cold grok plugin\n---\n",
    )
    stub_bin(
        root,
        "grok",
        """#!/bin/sh
if [ "$1" = "--version" ]; then echo grok 1.2.3; exit 0; fi
if [ "$1" = "inspect" ]; then
  cat <<'JSON'
{"grokVersion":"1.2.3","plugins":[
  {"name":"used-plugin","enabled":true},
  {"name":"cold-plugin","enabled":true}
],"skills":[{"name":"used-plugin","source":{"type":"plugin"}},
           {"name":"cold-plugin","source":{"type":"plugin"}}],
 "mcpServers":[{"name":"skillwiki"}],
 "hooks":[],
 "permissions":{"loaded":true}}
JSON
  exit 0
fi
exit 0
""",
    )
    for i in range(sessions):
        days_ago = 0 if sessions == 1 else span_days * i / max(sessions - 1, 1)
        folder = root / ".grok" / "sessions" / "demo" / f"{i:04d}"
        ts = iso_days_ago(days_ago)
        jsonl(
            folder / "events.jsonl",
            [
                {"ts": ts, "type": "tool_started", "tool_name": "read_file"},
                {"ts": ts, "type": "mcp_server_connected", "server_name": "skillwiki"},
                {
                    "ts": ts,
                    "type": "permission_resolved",
                    "tool_name": "read_file",
                    "decision": "allow",
                },
            ],
        )
        jsonl(
            folder / "chat_history.jsonl",
            [
                {"type": "user", "content": "/used-plugin" if i == 0 else "hello"},
                {
                    "type": "assistant",
                    "tool_calls": [
                        {
                            "name": "read_file",
                            "arguments": {
                                "target_file": "/x/skills/used-plugin/SKILL.md",
                                "prompt": SECRET_PROMPT,
                            },
                        }
                    ],
                },
            ],
        )
        touch_mtime(folder / "events.jsonl", days_ago)
        touch_mtime(folder / "chat_history.jsonl", days_ago)


def make_codex_home(root: Path) -> None:
    write(
        root / ".codex" / "config.toml",
        f"""
approval_policy = "on-request"
sandbox_mode = "workspace-write"
experimental_bearer_token = "{SECRET_BEARER}"

[plugins]
enabled = true
""",
    )
    write(root / ".codex" / "AGENTS.md", "codex agents\n")
    write(
        root / ".codex" / "plugins" / "cache" / "demo-plugin" / "skills" / "demo" / "SKILL.md",
        "---\nname: demo\ndescription: demo\n---\n",
    )
    rows = [
        {
            "type": "session_meta",
            "payload": {"cli_version": "0.153.4", "cwd": "/tmp"},
            "timestamp": iso_days_ago(1),
        },
        {
            "type": "response_item",
            "payload": {
                "type": "custom_tool_call",
                "name": "exec",
                "input": SECRET_PROMPT,
            },
        },
        {
            "type": "response_item",
            "payload": {"type": "message", "role": "user", "content": SECRET_PROMPT},
        },
    ]
    path = root / ".codex" / "sessions" / "2026" / "09" / "01" / "rollout-2026-09-01T00-00-00-demo.jsonl"
    jsonl(path, rows)
    touch_mtime(path, 1)
    stub_bin(root, "codex", "#!/bin/sh\necho codex 0.153.4\n")


def make_cursor_home(root: Path, *, stale: bool = True) -> None:
    write_json(
        root / ".cursor" / "cli-config.json",
        {
            "approvalMode": "allowlist",
            "sandbox": {"mode": "workspace"},
            "authInfo": {"email": SECRET_EMAIL, "authId": AUTH_ID},
        },
    )
    write(
        root / ".claude" / "plugins" / "cache" / "llm-wiki" / "skillwiki" / "0.10.56" / ".claude-plugin" / "plugin.json",
        json.dumps({"name": "skillwiki", "version": "0.10.56"}) + "\n",
    )
    write(
        root / ".claude" / "plugins" / "cache" / "llm-wiki" / "skillwiki" / "0.10.56" / "using-skillwiki" / "SKILL.md",
        "---\nname: using-skillwiki\n---\n",
    )
    pack_ver = "0.10.47" if stale else "0.10.56"
    write(
        root / ".cursor" / "plugins" / "marketplaces" / "github.com" / "karlorz" / "llm-wiki" / "abc" / ".claude-plugin" / "plugin.json",
        json.dumps({"name": "skillwiki", "version": pack_ver}) + "\n",
    )
    jsonl(
        root / ".cursor" / "prompt_history.jsonl",
        [{"command": "/skills", "text": "/skills"}, {"text": SECRET_PROMPT}],
    )
    touch_mtime(root / ".cursor" / "prompt_history.jsonl", 1)
    write_json(
        root / ".claude" / "settings.json",
        {"enabledPlugins": {"skillwiki@llm-wiki": True}},
    )


def findings_by_code(report: dict, harness: str, code: str) -> list[dict]:
    block = report["harnesses"][harness]
    return [item for item in block.get("findings") or [] if item.get("code") == code]


def test_bad_cli() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-cli-"))
    proc = run_doctor(home, ["--harness", "nope"])
    if proc.returncode == 2:
        ok("bad harness exit 2")
    else:
        fail("bad harness exit 2", f"exit {proc.returncode} {proc.stderr}")
    proc = run_doctor(home, ["--days", "0"])
    if proc.returncode == 2:
        ok("bad days exit 2")
    else:
        fail("bad days exit 2", f"exit {proc.returncode}")
    proc = run_doctor(Path("/tmp/does-not-exist-harness-doctor"), ["--json"])
    if proc.returncode == 2:
        ok("missing home exit 2")
    else:
        fail("missing home exit 2", f"exit {proc.returncode}")


def test_malformed_json() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-badjson-"))
    write(home / ".claude.json", "{not-json")
    write(home / ".claude" / "settings.json", "{}")
    proc = run_doctor(home, ["--harness", "claude", "--json"])
    if proc.returncode == 1 and "malformed" in proc.stderr:
        ok("malformed claude.json exit 1")
    else:
        fail("malformed claude.json exit 1", f"exit {proc.returncode} {proc.stderr}")


def test_claude_full() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-claude-"))
    make_claude_home(home, sessions=22, span_days=10)
    stub_bin(home, "claude", "#!/bin/sh\necho claude 2.1.263\n")
    proc = run_doctor(home, ["--harness", "claude", "--json", "--days", "30", "--limit", "50"])
    if proc.returncode != 0:
        fail("claude full exit", f"{proc.returncode} {proc.stderr}")
        return
    report = json.loads(proc.stdout)
    assert_no_secrets(proc.stdout + proc.stderr, "claude output redaction")
    codes = {item["code"] for item in report["harnesses"]["claude"]["findings"]}
    if "cold_candidate" in codes:
        targets = [item["target"] for item in findings_by_code(report, "claude", "cold_candidate")]
        if "cold-plugin@demo" in targets and "obsidian@obsidian-skills" not in targets:
            ok("claude cold plugin")
        else:
            fail("claude cold plugin", str(targets))
    else:
        fail("claude cold plugin", str(codes))
    if findings_by_code(report, "claude", "passive_unknown"):
        ok("claude passive not cold")
    else:
        fail("claude passive not cold", str(codes))
    if findings_by_code(report, "claude", "rare_keep"):
        ok("claude rare keep")
    else:
        fail("claude rare keep", str(codes))
    if findings_by_code(report, "claude", "duplicate"):
        ok("claude duplicate memory")
    else:
        fail("claude duplicate memory", str(codes))
    perm = findings_by_code(report, "claude", "permission_candidate")
    write_perm = findings_by_code(report, "claude", "permission_write")
    if perm and write_perm:
        ok("claude permission split")
    else:
        fail("claude permission split", f"cand={perm} write={write_perm}")
    window = report["harnesses"]["claude"]["usage"]["window"]
    if window.get("sufficient") is True:
        ok("claude sufficient window")
    else:
        fail("claude sufficient window", str(window))


def test_insufficient_window() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-thin-"))
    make_claude_home(home, sessions=5, span_days=2)
    proc = run_doctor(home, ["--harness", "claude", "--json", "--days", "30", "--limit", "50"])
    report = json.loads(proc.stdout)
    codes = {item["code"] for item in report["harnesses"]["claude"]["findings"]}
    if "cold_candidate" not in codes:
        ok("thin window withholds retirement")
    else:
        fail("thin window withholds retirement", str(codes))
    if any("insufficient window" in item for item in report["harnesses"]["claude"]["limitations"]):
        ok("thin window limitation")
    else:
        fail("thin window limitation", str(report["harnesses"]["claude"]["limitations"]))


def grok_inspect_stub(body: str) -> str:
    return (
        "#!/bin/sh\n"
        'if [ "$1" = "--version" ]; then echo grok 1.2.3; exit 0; fi\n'
        'if [ "$1" = "inspect" ]; then\n'
        f"{body}\n"
        "fi\n"
        "exit 0\n"
    )


def inspect_payload() -> dict:
    return {
        "grokVersion": "1.0.45",
        "plugins": [
            {"name": "live-plugin", "enabled": True},
            {"name": "off-plugin", "enabled": False},
        ],
        "skills": [
            {
                "name": "collide",
                "description": "plugin copy of a collided name",
                "source": {"type": "plugin", "plugin_name": "live-plugin", "path": "/secret/live/SKILL.md"},
                "userInvocable": True,
            },
            {
                "name": "collide",
                "description": "user copy of a collided name",
                "source": {"type": "user", "path": "/secret/user/SKILL.md"},
                "userInvocable": True,
            },
            {
                "name": "folded",
                "description": f"folded description with {SECRET_KEY} and {SECRET_EMAIL}",
                "source": {"type": "bundled", "path": f"/secret/{SECRET_BEARER}/SKILL.md"},
                "userInvocable": False,
            },
            {
                "name": "off-skill",
                "description": "defined by a disabled plugin",
                "source": {"type": "plugin", "plugin_name": "off-plugin", "path": "/secret/off/SKILL.md"},
                "userInvocable": True,
            },
        ],
        "mcpServers": [{"name": "skillwiki"}],
        "hooks": [],
        "permissions": {"loaded": True},
        "cwd": "/secret/workspace",
        "configSources": {"layers": [{"role": "user", "path": "/secret/config.toml"}]},
    }


def make_grok_inspect_home(root: Path, payload: dict, *, behavior: str = "ok") -> None:
    write(
        root / ".grok" / "config.toml",
        """
[plugins]
enabled = ["live-plugin"]
""",
    )
    write(root / ".grok" / "AGENTS.md", "agent rules\n")
    write(
        root / ".grok" / "installed-plugins" / "live-plugin" / "skills" / "collide" / "SKILL.md",
        "---\nname: collide\ndescription: installed copy\n---\n",
    )
    write_json(root / ".grok" / "inspect-fixture.json", payload)
    if behavior == "timeout":
        body = "sleep 5"
    elif behavior == "malformed":
        body = "printf '%s' '{not-json'"
    elif behavior == "failed":
        body = "printf '%s' 'boom' >&2; exit 3"
    else:
        body = 'cat "${HOME}/.grok/inspect-fixture.json"'
    record = root / ".grok" / "inspect-probe.txt"
    stub_bin(
        root,
        "grok",
        grok_inspect_stub(
            'printf "%s|%s|%s\\n" "$HOME" "$PWD" "${GROK_HOME:-unset}" >> '
            f'"{record}"\n' + body
        ),
    )


def test_grok_inspect_metrics() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-inspect-"))
    payload = inspect_payload()
    make_grok_inspect_home(home, payload)
    proc = run_doctor(home, ["--harness", "grok", "--json"])
    if proc.returncode != 0:
        fail("inspect metrics exit", f"{proc.returncode} {proc.stderr}")
        return
    report = json.loads(proc.stdout)
    grok = report["harnesses"]["grok"]
    context = grok["context"]
    discovered = context["discovered"]
    if discovered["status"] == "OK" and discovered["basis"].startswith("grok inspect"):
        ok("inspect metrics discovered basis")
    else:
        fail("inspect metrics discovered basis", str(discovered))
    if discovered["discovered_rows"] == 4 and discovered["unique_names"] == 3:
        ok("inspect metrics row and unique counts")
    else:
        fail("inspect metrics row and unique counts", str(discovered))
    if discovered["duplicate_rows"] == 1 and discovered["duplicate_name_groups"]:
        group = discovered["duplicate_name_groups"][0]
        if group["name"] == "collide" and sorted(group["sources"]) == ["plugin:live-plugin", "user"]:
            ok("inspect metrics duplicate group sources")
        else:
            fail("inspect metrics duplicate group sources", str(group))
    else:
        fail("inspect metrics duplicate group", str(discovered))
    breakdown = discovered["source_breakdown"]
    if breakdown == {"bundled": 1, "plugin": 2, "user": 1}:
        ok("inspect metrics source breakdown")
    else:
        fail("inspect metrics source breakdown", str(breakdown))
    total = discovered["description_tokens"]
    unique = discovered["unique_description_tokens"]
    if total > unique > 0:
        ok("inspect metrics keep duplicate rows in estimate")
    else:
        fail("inspect metrics keep duplicate rows in estimate", f"{total} vs {unique}")
    if discovered["model_visible"] == "UNKNOWN" and grok["extensions"]["skills_source"].startswith(
        "grok inspect"
    ):
        ok("inspect metrics model visibility unknown")
    else:
        fail("inspect metrics model visibility unknown", str(discovered))
    if findings_by_code(report, "grok", "duplicate_skill_name"):
        ok("inspect metrics duplicate finding")
    else:
        fail("inspect metrics duplicate finding", str(grok["findings"]))
    codes = {item["code"] for item in grok["findings"]}
    if "context_discovered_ok" in codes and "context_ok" in codes:
        ok("inspect metrics separate static and discovered findings")
    else:
        fail("inspect metrics separate static and discovered findings", str(codes))
    blob = proc.stdout + proc.stderr
    if "/secret/" not in blob and "inspect-fixture" not in blob:
        ok("inspect metrics redact sources")
    else:
        fail("inspect metrics redact sources", blob[:400])
    assert_no_secrets(blob, "inspect metrics redact secrets")
    # Disabled plugins are inspect-authoritative: the off-plugin row still appears.
    if any(row.get("name") == "off-plugin" for row in grok["extensions"]["plugins"]):
        ok("inspect metrics keep disabled plugin rows")
    else:
        fail("inspect metrics keep disabled plugin rows", str(grok["extensions"]["plugins"]))
    probe = (home / ".grok" / "inspect-probe.txt").read_text(encoding="utf-8").strip().split("|")
    if (
        len(probe) == 3
        and Path(probe[0]).resolve() == home.resolve()
        and Path(probe[1]).resolve() == home.resolve()
        and Path(probe[2]).resolve() == (home / ".grok").resolve()
    ):
        ok("inspect probe bound to fixture home")
    else:
        fail("inspect probe bound to fixture home", str(probe))


def test_grok_inspect_unavailable() -> None:
    for bad_rows in (42, {"name": "wrong shape"}, ["invalid row"]):
        home = Path(tempfile.mkdtemp(prefix="hd-inspect-shape-"))
        payload = inspect_payload()
        payload["skills"] = bad_rows
        make_grok_inspect_home(home, payload)
        proc = run_doctor(home, ["--harness", "grok", "--json"])
        if proc.returncode == 0:
            discovered = json.loads(proc.stdout)["harnesses"]["grok"]["context"]["discovered"]
            if discovered["status"] == "UNKNOWN" and discovered.get("reason") == "malformed":
                ok("inspect invalid row shape is UNKNOWN")
                continue
        fail("inspect invalid row shape is UNKNOWN", "invalid inspect shape was accepted or crashed")
    for behavior, label in (("malformed", "malformed"), ("failed", "failed")):
        home = Path(tempfile.mkdtemp(prefix=f"hd-inspect-{behavior}-"))
        make_grok_inspect_home(home, inspect_payload(), behavior=behavior)
        proc = run_doctor(home, ["--harness", "grok", "--json"])
        if proc.returncode != 0:
            fail(f"inspect {label} exit", f"{proc.returncode} {proc.stderr}")
            continue
        report = json.loads(proc.stdout)
        discovered = report["harnesses"]["grok"]["context"]["discovered"]
        if discovered["status"] == "UNKNOWN" and discovered.get("reason") == behavior:
            ok(f"inspect {label} is UNKNOWN")
        else:
            fail(f"inspect {label} is UNKNOWN", str(discovered))
        codes = {item["code"] for item in report["harnesses"]["grok"]["findings"]}
        if "context_discovered_unknown" in codes and "duplicate_skill_names_unknown" in codes:
            ok(f"inspect {label} findings unknown")
        else:
            fail(f"inspect {label} findings unknown", str(codes))

    home = Path(tempfile.mkdtemp(prefix="hd-inspect-timeout-"))
    make_grok_inspect_home(home, inspect_payload(), behavior="timeout")
    proc = run_doctor(home, ["--harness", "grok", "--json"], env_extra={"HARNESS_DOCTOR_INSPECT_TIMEOUT": "0.3"})
    report = json.loads(proc.stdout)
    discovered = report["harnesses"]["grok"]["context"]["discovered"]
    if discovered["status"] == "UNKNOWN" and discovered.get("reason") == "timeout":
        ok("inspect timeout is UNKNOWN")
    else:
        fail("inspect timeout is UNKNOWN", str(discovered))

    empty = home / "empty-bin"
    empty.mkdir(exist_ok=True)
    proc = run_doctor(home, ["--harness", "grok", "--json"], path_dir=empty)
    report = json.loads(proc.stdout)
    discovered = report["harnesses"]["grok"]["context"]["discovered"]
    if discovered["status"] == "UNKNOWN" and discovered.get("reason") == "missing_cli":
        ok("inspect missing CLI is UNKNOWN")
    else:
        fail("inspect missing CLI is UNKNOWN", str(discovered))


def test_grok_static_labels() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-static-"))
    make_grok_inspect_home(home, inspect_payload())
    proc = run_doctor(home, ["--harness", "grok", "--json"])
    report = json.loads(proc.stdout)
    context = report["harnesses"]["grok"]["context"]
    if context.get("kind") == "static installed-file catalog" and "ignores enable/ignore" in context.get(
        "static_note", ""
    ):
        ok("static context labelled")
    else:
        fail("static context labelled", str(context))
    if "UTF-8 bytes / 4" in str(context.get("token_estimate")):
        ok("static context estimate named")
    else:
        fail("static context estimate named", str(context.get("token_estimate")))
    human = run_doctor(home, ["--harness", "grok"])
    if "local heuristic threshold" in human.stdout or "discovered" in human.stdout:
        ok("human report explains context basis")
    else:
        fail("human report explains context basis", human.stdout[:600])


def test_grok_inspect_authoritative() -> None:
    """Ignored/disabled definitions: inspect decides, static disk does not."""
    home = Path(tempfile.mkdtemp(prefix="hd-inspect-auth-"))
    payload = inspect_payload()
    make_grok_inspect_home(home, payload)
    write(
        home / ".grok" / "config.toml",
        '[plugins]\nenabled = ["live-plugin"]\n\n[skills]\nignore = ["ignored-skill"]\n',
    )
    write(
        home / ".grok" / "installed-plugins" / "off-plugin" / "skills" / "ignored-skill" / "SKILL.md",
        "---\nname: ignored-skill\ndescription: ignored on disk\n---\n",
    )
    proc = run_doctor(home, ["--harness", "grok", "--json"])
    report = json.loads(proc.stdout)
    grok = report["harnesses"]["grok"]
    names = {row["name"] for row in grok["extensions"]["skills"]}
    if "ignored-skill" not in names:
        ok("ignored skill absent from inspect rows")
    else:
        fail("ignored skill absent from inspect rows", str(names))
    discovered = grok["context"]["discovered"]
    if discovered["status"] == "OK" and discovered["unique_names"] == 3:
        ok("discovered count stays inspect-authoritative")
    else:
        fail("discovered count stays inspect-authoritative", str(discovered))
    if grok["context"]["plugin_catalog_skills"] == 2:
        ok("static count still includes ignored installed file")
    else:
        fail("static count still includes ignored installed file", str(grok["context"]))


def test_grok() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-grok-"))
    make_grok_home(home, sessions=22, span_days=10)
    proc = run_doctor(home, ["--harness", "grok", "--json", "--days", "30", "--limit", "50"])
    if proc.returncode != 0:
        fail("grok exit", f"{proc.returncode} {proc.stderr}\n{proc.stdout}")
        return
    blob = proc.stdout + proc.stderr
    assert_no_secrets(blob, "grok output redaction")
    if "should-not-run" in blob:
        fail("grok did not launch learn", blob[:300])
    else:
        ok("grok did not launch learn")
    report = json.loads(proc.stdout)
    if findings_by_code(report, "grok", "learn_follow_up"):
        ok("grok learn follow-up")
    else:
        fail("grok learn follow-up", str(report["harnesses"]["grok"]["findings"]))
    if report["harnesses"]["grok"]["config"]["learn"]["launched"] is False:
        ok("grok learn launched false")
    else:
        fail("grok learn launched false", str(report["harnesses"]["grok"]["config"]["learn"]))
    if (home / ".grok" / "learn").exists():
        fail("grok wrote learn state", "learn dir created")
    else:
        ok("grok wrote no learn state")
    cold = findings_by_code(report, "grok", "cold_candidate")
    unknown = findings_by_code(report, "grok", "usage_unknown")
    if not cold and not unknown:
        ok("grok missing counters are not cold")
    else:
        fail("grok missing counters are not cold", f"cold={cold} unknown={unknown}")


def test_codex_and_cursor() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-cc-"))
    make_codex_home(home)
    make_cursor_home(home, stale=True)
    proc = run_doctor(home, ["--harness", "all", "--json", "--days", "30", "--limit", "50"])
    if proc.returncode != 0:
        fail("codex/cursor exit", f"{proc.returncode} {proc.stderr}")
        return
    assert_no_secrets(proc.stdout + proc.stderr, "codex/cursor redaction")
    report = json.loads(proc.stdout)
    secret_keys = report["harnesses"]["codex"]["config"].get("secret_keys_redacted")
    if secret_keys:
        ok("codex redacted secret keys")
    else:
        fail("codex redacted secret keys", str(report["harnesses"]["codex"]["config"]))
    if findings_by_code(report, "cursor", "cursor_pack_stale"):
        ok("cursor stale pack")
    else:
        fail("cursor stale pack", str(report["harnesses"]["cursor"]["findings"]))
    if "authInfo" not in json.dumps(report["harnesses"]["cursor"]):
        ok("cursor authInfo omitted")
    else:
        fail("cursor authInfo omitted", "authInfo present")


def test_missing_cli_unknown() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-nocli-"))
    make_claude_home(home, sessions=3, span_days=1)
    empty = home / "empty-bin"
    empty.mkdir(exist_ok=True)
    proc = run_doctor(home, ["--harness", "claude", "--json"], path_dir=empty)
    report = json.loads(proc.stdout)
    version = report["harnesses"]["claude"]["version"]
    if version["status"] == "UNKNOWN":
        ok("missing claude CLI is UNKNOWN")
    else:
        fail("missing claude CLI is UNKNOWN", str(version))


def test_windows_style_home() -> None:
    base = Path(tempfile.mkdtemp(prefix="hd-win-"))
    home = base / "C" / "Users" / "fixture"
    make_claude_home(home, sessions=3, span_days=1)
    proc = run_doctor(home, ["--harness", "claude", "--json"])
    if proc.returncode == 0 and "claude" in json.loads(proc.stdout)["harnesses"]:
        ok("windows-style home path")
    else:
        fail("windows-style home path", f"{proc.returncode} {proc.stderr}")


def test_module_helpers() -> None:
    mod = load_mod()
    fixture_home = Path("/tmp/doctor-isolated-user")
    with patch.dict(os.environ, {
        "USERPROFILE": "/operator",
        "GROK_HOME": "/operator/.grok",
        "GROK_CONFIG": '{"agent":"operator"}',
        "GROK_CONFIG_PATH": "/operator/overlay.toml",
    }):
        env = mod.bound_env(fixture_home)
    if all(env[key] == str(fixture_home) for key in ("HOME", "USERPROFILE")) and env["GROK_HOME"] == str(fixture_home / ".grok"):
        ok("probe binds Unix and Windows home paths")
    else:
        fail("probe binds Unix and Windows home paths", str(env.get("USERPROFILE")))
    if "GROK_CONFIG" not in env and "GROK_CONFIG_PATH" not in env and env.get("GROK_DISABLE_AUTOUPDATER") == "1":
        ok("probe removes inherited overlays and disables updates")
    else:
        fail("probe removes inherited overlays and disables updates", "unexpected probe environment")
    if mod.permission_class("git status") == "read" and mod.permission_class("git push") == "write":
        ok("permission_class")
    else:
        fail("permission_class", f"{mod.permission_class('git status')} {mod.permission_class('git push')}")
    redacted = mod.redact_text(f"Bearer secret-token {SECRET_EMAIL}")
    if "secret-token" not in redacted and SECRET_EMAIL not in redacted:
        ok("redact_text")
    else:
        fail("redact_text", redacted)
    dumped = mod.dump_json({"experimental_bearer_token": SECRET_BEARER, "content": SECRET_PROMPT})
    if SECRET_BEARER not in dumped and SECRET_PROMPT not in dumped:
        ok("dump_json redacts secret keys and prompts")
    else:
        fail("dump_json redacts secret keys and prompts", dumped)


def test_standalone_frontmatter_parity() -> None:
    mod = load_mod()
    spec = importlib.util.spec_from_file_location(
        "inventory_test_fixtures", ROOT / "scripts" / "test-context-budget-inventory.py"
    )
    assert spec and spec.loader
    fixtures = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixtures)
    budget = mod.try_load_context_budget()
    assert budget is not None
    cases = fixtures.frontmatter_cases() + [
        ("BOM+CRLF", "\ufeff---\r\nname: zeta\r\ndescription: >-\r\n  first\r\n  second\r\n---\r\n", ("zeta", "first second")),
        ("plain continuation", "---\nname: eta\ndescription: first\n  second\n---\n", ("eta", "first second")),
        ("quoted continuation", '---\nname: theta\ndescription: "first\n  second"\n---\n', ("theta", "first second")),
    ]
    for label, text, (name, desc) in cases:
        actual = mod._fallback_parse_frontmatter(text)
        if actual == budget.parse_skill_frontmatter(text) == {"name": name, "description": desc}:
            ok(f"standalone frontmatter parity: {label}")
        else:
            fail(f"standalone frontmatter parity: {label}", str(actual))


def test_grok_version_probe_fallback() -> None:
    mod = load_mod()
    home = Path(tempfile.mkdtemp(prefix="hd-version-"))
    (home / ".grok").mkdir()
    for label, state, payload, expected, calls in (
        ("inspect version", "ok", {"grokVersion": "1.0.45", "skills": []}, "1.0.45", 0),
        ("missing inspect version", "ok", {"skills": []}, "fallback-version", 1),
        ("unavailable inspect", "failed", None, "fallback-version", 1),
    ):
        with patch.object(mod, "grok_inspect", return_value={"state": state, "data": payload}), patch.object(
            mod, "cli_version", return_value="fallback-version"
        ) as version:
            result = mod.audit_grok(home, 30, 50)
        if result["version"]["value"] == expected and version.call_count == calls:
            ok(f"grok version probe: {label}")
        else:
            fail(f"grok version probe: {label}", str(result["version"]))


def test_human_and_schema() -> None:
    home = Path(tempfile.mkdtemp(prefix="hd-human-"))
    make_claude_home(home, sessions=3, span_days=1)
    proc = run_doctor(home, ["--harness", "claude"])
    if proc.returncode == 0 and "Read-only" in proc.stdout and "harness-doctor.v1" in proc.stdout:
        ok("human report")
    else:
        fail("human report", proc.stdout[:400])
    proc = run_doctor(home, ["--harness", "claude", "--json"])
    report = json.loads(proc.stdout)
    if report.get("schema") == "harness-doctor.v1" and report.get("read_only") is True:
        ok("schema version")
    else:
        fail("schema version", str(report.get("schema")))


def main() -> int:
    test_bad_cli()
    test_malformed_json()
    test_claude_full()
    test_insufficient_window()
    test_grok()
    test_grok_inspect_authoritative()
    test_grok_inspect_metrics()
    test_grok_inspect_unavailable()
    test_grok_static_labels()
    test_codex_and_cursor()
    test_missing_cli_unknown()
    test_windows_style_home()
    test_module_helpers()
    test_standalone_frontmatter_parity()
    test_grok_version_probe_fallback()
    test_human_and_schema()
    print(f"\n=== Results: {PASS} passed, {FAIL} failed ===")
    return 1 if FAIL else 0


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="harness-doctor-tests-", dir="/tmp") as test_root:
        with patch.object(tempfile, "tempdir", test_root):
            raise SystemExit(main())
