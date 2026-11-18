#!/usr/bin/env python3
"""fleet-board-burn portable MCP launcher fixture.

JSON/hash manifest parity plus isolated launcher stubs. Stubs fake `uname -s`
so Darwin and Linux branches both run on a Mac host. Does not call the live
Fleet Board. Catalog inventory stays in scripts/test-dev-loop-release-tooling.sh.
"""
from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PLUGIN = REPO / "skills" / "fleet-board-burn"
LAUNCHER = PLUGIN / "scripts" / "fleet-board-burn-mcp"
VERSION = json.loads((PLUGIN / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))["version"]
PLUGIN_ARG = "${CLAUDE_PLUGIN_ROOT}/scripts/fleet-board-burn-mcp"
BOX_PY = "/workspace/code/fleet-board/tools/agent-read/burn_read.py"
DEFAULT_LOOPBACK = "http://127.0.0.1:18099"
DEFAULT_TOKEN_REL = Path(".config") / "fleet-board" / "agent-read.env"
MAC_BIN_REL = Path(".local") / "bin" / "fleet-board-burn-mcp"


def fail(message: str) -> None:
    raise SystemExit(message)


def load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{path}: invalid JSON: {exc}")


def sha256_text(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_exec(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IRUSR | stat.S_IWUSR)


STUB_BODY = """\
#!/bin/sh
printf 'exe=%s\\n' "$0"
printf 'argc=%s\\n' "$#"
i=0
for a in "$@"; do
  i=$((i + 1))
  printf 'arg%s=%s\\n' "$i" "$a"
done
printf 'token=%s\\n' "${FLEET_BOARD_AGENT_TOKEN_FILE-UNSET}"
printf 'url=%s\\n' "${FLEET_BOARD_AGENT_URL-UNSET}"
"""


def parse_stub(stdout: str) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in stdout.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key] = value
    return data


def uname_bindir(root: Path, sysname: str) -> Path:
    bindir = root / f"uname-{sysname}"
    write_exec(
        bindir / "uname",
        "#!/bin/sh\nprintf '%s\\n' '%s'\n" % ("%s", sysname),
    )
    return bindir


def launcher_env(home: Path, uname_dir: Path, extra: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("FLEET_BOARD_"):
            env.pop(key, None)
    env["HOME"] = str(home)
    env["PATH"] = str(uname_dir) + os.pathsep + env.get("PATH", "/usr/bin:/bin")
    if extra:
        env.update(extra)
    return env


def run_launcher(env: dict[str, str], args: list[str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(LAUNCHER), *(args or [])],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )


def expect_ok(label: str, proc: subprocess.CompletedProcess[str]) -> dict[str, str]:
    if proc.returncode != 0:
        fail(f"{label}: expected exit 0, got {proc.returncode}: {proc.stderr!r} {proc.stdout!r}")
    return parse_stub(proc.stdout)


def expect_fail(label: str, proc: subprocess.CompletedProcess[str], needle: str) -> None:
    if proc.returncode == 0:
        fail(f"{label}: expected failure, got stdout {proc.stdout!r}")
    if needle not in proc.stderr:
        fail(f"{label}: stderr missing {needle!r}: {proc.stderr!r}")


def check_manifest_parity() -> str:
    mcp = PLUGIN / ".mcp.json"
    cursor_mcp = PLUGIN / "mcp.json"
    digest = sha256_text(mcp)
    if digest != sha256_text(cursor_mcp):
        fail("mcp.json parity: .mcp.json and mcp.json hashes differ")
    expected = {
        "command": "bash",
        "args": [PLUGIN_ARG],
    }
    for path in (mcp, cursor_mcp):
        data = load_json(path)
        if not isinstance(data, dict):
            fail(f"{path}: root must be an object")
        servers = data.get("mcpServers")
        if not isinstance(servers, dict) or set(servers) != {"fleet-board-burn"}:
            fail(f"{path}: mcpServers must contain only fleet-board-burn")
        server = servers["fleet-board-burn"]
        if server.get("command") != expected["command"]:
            fail(f"{path}: command must be bash")
        if server.get("args") != expected["args"]:
            fail(f"{path}: args must be {expected['args']!r}")
        if "env" in server:
            fail(f"{path}: must not pin env")
        blob = path.read_text(encoding="utf-8")
        if "/Users/" in blob or "karlchow" in blob:
            fail(f"{path}: must not hardcode Mac user paths")
        if "FLEET_BOARD_AGENT_TOKEN_FILE" in blob:
            fail(f"{path}: must not hardcode FLEET_BOARD_AGENT_TOKEN_FILE")
    claude = load_json(PLUGIN / ".claude-plugin" / "plugin.json")
    codex = load_json(PLUGIN / ".codex-plugin" / "plugin.json")
    cursor = load_json(PLUGIN / ".cursor-plugin" / "plugin.json")
    if not isinstance(claude, dict) or claude.get("version") != VERSION:
        fail("Claude manifest version mismatch")
    if not isinstance(codex, dict) or codex.get("version") != VERSION:
        fail("Codex manifest version mismatch")
    if not isinstance(cursor, dict) or cursor.get("version") != VERSION:
        fail("Cursor manifest version mismatch")
    if cursor.get("mcpServers") != "./mcp.json":
        fail("Cursor mcpServers must point to ./mcp.json")
    if isinstance(codex, dict) and "mcpServers" in codex:
        fail("Codex overlay must omit mcpServers")
    marketplace = load_json(REPO / ".claude-plugin" / "marketplace.json")
    if not isinstance(marketplace, dict):
        fail("marketplace.json must be an object")
    plugins = marketplace.get("plugins")
    if not isinstance(plugins, list):
        fail("marketplace plugins must be a list")
    entry = next((item for item in plugins if isinstance(item, dict) and item.get("name") == "fleet-board-burn"), None)
    if entry is None or entry.get("version") != VERSION:
        fail("Claude marketplace fleet-board-burn version mismatch")
    src = LAUNCHER.read_text(encoding="utf-8")
    if "FLEET_BOARD_LOCAL_TEST" in src:
        fail("launcher must not set unused FLEET_BOARD_LOCAL_TEST")
    if "shift" not in src:
        fail("launcher must shift argv before exec")
    if "/Users/karlchow" in src:
        fail("launcher must not hardcode /Users/karlchow")
    readme = (PLUGIN / "README.md").read_text(encoding="utf-8")
    for needle in (PLUGIN_ARG, str(DEFAULT_TOKEN_REL), DEFAULT_LOOPBACK, "Fail closed"):
        if needle not in readme:
            fail(f"README.md missing {needle!r}")
    return digest


def check_runtime_stubs() -> None:
    with tempfile.TemporaryDirectory() as raw_tmp:
        tmp = Path(raw_tmp)
        space_home = tmp / "user with spaces"
        mac_bin = space_home / MAC_BIN_REL
        default_token = space_home / DEFAULT_TOKEN_REL
        write_exec(mac_bin, STUB_BODY)
        default_token.parent.mkdir(parents=True, exist_ok=True)
        default_token.write_text("CF_ACCESS_CLIENT_ID=id\nCF_ACCESS_CLIENT_SECRET=secret\n", encoding="utf-8")
        default_token.chmod(stat.S_IRUSR | stat.S_IWUSR)

        stub_py = tmp / "python with spaces" / "python3"
        write_exec(stub_py, STUB_BODY)
        stub_read = tmp / "read with spaces" / "burn_read.py"
        stub_read.parent.mkdir(parents=True, exist_ok=True)
        stub_read.write_text("# stub\n", encoding="utf-8")

        alt_token = tmp / "token dir" / "explicit.env"
        alt_token.parent.mkdir(parents=True, exist_ok=True)
        alt_token.write_text("CF_ACCESS_CLIENT_ID=id\nCF_ACCESS_CLIENT_SECRET=secret\n", encoding="utf-8")
        alt_token.chmod(stat.S_IRUSR | stat.S_IWUSR)

        darwin = uname_bindir(tmp, "Darwin")
        linux = uname_bindir(tmp, "Linux")
        other = uname_bindir(tmp, "FreeBSD")

        # Darwin default token + argc 0
        proc = run_launcher(launcher_env(space_home, darwin))
        data = expect_ok("darwin default token", proc)
        if data.get("exe") != str(mac_bin):
            fail(f"darwin default token exe: {data}")
        if data.get("argc") != "0":
            fail(f"darwin default token argc: {data}")
        if data.get("token") != str(default_token):
            fail(f"darwin default token path: {data}")

        # Darwin exact extra argv
        proc = run_launcher(launcher_env(space_home, darwin), ["foo", "bar baz"])
        data = expect_ok("darwin extra argv", proc)
        if data.get("argc") != "2" or data.get("arg1") != "foo" or data.get("arg2") != "bar baz":
            fail(f"darwin extra argv: {data}")

        # Darwin literal ~/ expansion + export
        proc = run_launcher(
            launcher_env(
                space_home,
                darwin,
                {"FLEET_BOARD_AGENT_TOKEN_FILE": "~/.config/fleet-board/agent-read.env"},
            )
        )
        data = expect_ok("darwin tilde token", proc)
        if data.get("token") != str(default_token):
            fail(f"darwin tilde token not normalized: {data}")
        if data.get("token").startswith("~"):
            fail(f"darwin tilde token leaked literal tilde: {data}")

        # Darwin explicit token
        proc = run_launcher(
            launcher_env(
                space_home,
                darwin,
                {"FLEET_BOARD_AGENT_TOKEN_FILE": str(alt_token)},
            )
        )
        data = expect_ok("darwin explicit token", proc)
        if data.get("token") != str(alt_token):
            fail(f"darwin explicit token: {data}")

        # Darwin missing default token
        empty_home = tmp / "empty darwin"
        empty_home.mkdir()
        write_exec(empty_home / MAC_BIN_REL, STUB_BODY)
        proc = run_launcher(launcher_env(empty_home, darwin))
        expect_fail("darwin missing token", proc, "FLEET_BOARD_AGENT_TOKEN_FILE")

        # Darwin missing launcher
        no_bin_home = tmp / "no bin"
        no_bin_home.mkdir()
        (no_bin_home / DEFAULT_TOKEN_REL).parent.mkdir(parents=True)
        (no_bin_home / DEFAULT_TOKEN_REL).write_text("x\n", encoding="utf-8")
        proc = run_launcher(launcher_env(no_bin_home, darwin))
        expect_fail("darwin missing launcher", proc, "missing Mac Access launcher")

        # Linux loopback default + exact argv
        linux_home = tmp / "linux home"
        linux_home.mkdir()
        proc = run_launcher(
            launcher_env(
                linux_home,
                linux,
                {
                    "FLEET_BOARD_PYTHON": str(stub_py),
                    "FLEET_BOARD_BOX_PY": str(stub_read),
                },
            )
        )
        data = expect_ok("linux loopback", proc)
        if data.get("exe") != str(stub_py):
            fail(f"linux loopback exe: {data}")
        if data.get("argc") != "2" or data.get("arg1") != str(stub_read) or data.get("arg2") != "mcp":
            fail(f"linux loopback argv: {data}")
        if data.get("token") != "":
            fail(f"linux loopback token must be empty: {data}")
        if data.get("url") != DEFAULT_LOOPBACK:
            fail(f"linux loopback url: {data}")

        # Linux extra argv after mcp
        proc = run_launcher(
            launcher_env(
                linux_home,
                linux,
                {
                    "FLEET_BOARD_PYTHON": str(stub_py),
                    "FLEET_BOARD_BOX_PY": str(stub_read),
                },
            ),
            ["status"],
        )
        data = expect_ok("linux extra argv", proc)
        if (
            data.get("argc") != "3"
            or data.get("arg1") != str(stub_read)
            or data.get("arg2") != "mcp"
            or data.get("arg3") != "status"
        ):
            fail(f"linux extra argv: {data}")

        # Linux preserve explicit safe loopback
        proc = run_launcher(
            launcher_env(
                linux_home,
                linux,
                {
                    "FLEET_BOARD_PYTHON": str(stub_py),
                    "FLEET_BOARD_BOX_PY": str(stub_read),
                    "FLEET_BOARD_AGENT_URL": "http://127.0.0.1:19999",
                },
            )
        )
        data = expect_ok("linux preserve loopback", proc)
        if data.get("url") != "http://127.0.0.1:19999":
            fail(f"linux preserve loopback: {data}")

        # Linux explicit token keeps Access (do not force loopback URL)
        proc = run_launcher(
            launcher_env(
                linux_home,
                linux,
                {
                    "FLEET_BOARD_PYTHON": str(stub_py),
                    "FLEET_BOARD_BOX_PY": str(stub_read),
                    "FLEET_BOARD_AGENT_TOKEN_FILE": str(alt_token),
                },
            )
        )
        data = expect_ok("linux explicit token", proc)
        if data.get("token") != str(alt_token):
            fail(f"linux explicit token: {data}")
        if data.get("url") != "UNSET":
            fail(f"linux explicit token must not force URL: {data}")

        # Linux missing backend
        proc = run_launcher(
            launcher_env(
                linux_home,
                linux,
                {
                    "FLEET_BOARD_PYTHON": str(stub_py),
                    "FLEET_BOARD_BOX_PY": str(tmp / "missing burn_read.py"),
                },
            )
        )
        expect_fail("linux missing backend", proc, "missing BOX read-only Python path")

        # BIN override with spaces, exact argv, independent of uname
        space_bin = tmp / "bin with spaces" / "fleet-board-burn-mcp"
        write_exec(space_bin, STUB_BODY)
        proc = run_launcher(
            launcher_env(
                space_home,
                other,
                {"FLEET_BOARD_BURN_MCP_BIN": str(space_bin)},
            ),
            ["only"],
        )
        data = expect_ok("bin override argv", proc)
        if data.get("exe") != str(space_bin) or data.get("argc") != "1" or data.get("arg1") != "only":
            fail(f"bin override argv: {data}")
        if data.get("token") != str(default_token):
            fail(f"bin override default token: {data}")

        # Missing BIN override
        proc = run_launcher(
            launcher_env(
                space_home,
                darwin,
                {"FLEET_BOARD_BURN_MCP_BIN": str(tmp / "no such bin")},
            )
        )
        expect_fail("missing bin override", proc, "not found")

        secret = "s3cret"
        bad_urls = (
            ("userinfo", f"http://user:{secret}@127.0.0.1:18099", "userinfo"),
            ("port-at-remote", "http://127.0.0.1:80@evil.example", "userinfo"),
            ("invalid-port", "http://127.0.0.1:65536", "loopback"),
            ("path", "http://127.0.0.1:18099/hidden", "loopback"),
            ("query", f"http://127.0.0.1:18099?token={secret}", "loopback"),
        )
        for label, url, needle in bad_urls:
            proc = run_launcher(
                launcher_env(
                    linux_home,
                    linux,
                    {
                        "FLEET_BOARD_PYTHON": str(stub_py),
                        "FLEET_BOARD_BOX_PY": str(stub_read),
                        "FLEET_BOARD_AGENT_URL": url,
                    },
                )
            )
            expect_fail(f"malformed url {label}", proc, needle)
            if secret in proc.stderr or secret in proc.stdout:
                fail(f"malformed url {label}: secret leaked")

        # Unsupported OS
        proc = run_launcher(launcher_env(space_home, other))
        expect_fail("unsupported os", proc, "unsupported OS")


def main() -> int:
    if not LAUNCHER.is_file():
        fail(f"missing launcher {LAUNCHER}")
    digest = check_manifest_parity()
    check_runtime_stubs()
    print("test-fleet-board-burn-plugin: ok")
    print(f"mcp parity sha256={digest}")
    print(f"version={VERSION}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
