#!/usr/bin/env python3
"""Targeted regression tests for config preservation and installation.

Covers generate-config.py's host-state merge (skill/plugin path arrays, absent
scalars, unsupported shapes, malformed input, missing parser) and
install-config.py's staged/validated/atomic install (stale-hash conflict,
backup, permissions, symlinks).

Run: python3 scripts/test-grok-build-harness-config.py
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
import textwrap
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "skills" / "grok-build-harness" / "scripts"
TEMPLATE = ROOT / "skills" / "grok-build-harness" / "assets" / "config.toml.template"
GENERATE = SCRIPTS / "generate-config.py"
INSTALL_CONFIG = SCRIPTS / "install-config.py"

PASS = 0
FAIL = 0


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


generate = load_module("generate_config_under_test", GENERATE)
installer = load_module("install_config_under_test", INSTALL_CONFIG)


def ok(label: str) -> None:
    global PASS
    PASS += 1
    print(f"ok:   {label}")


def fail(label: str) -> None:
    global FAIL
    FAIL += 1
    print(f"FAIL: {label}")


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        ok(label)
    else:
        fail(f"{label}{': ' + detail if detail else ''}")


def raises(label: str, exc_type, fn, *args) -> None:
    try:
        fn(*args)
    except exc_type:
        ok(label)
    except Exception as exc:  # noqa: BLE001 - report the wrong failure type
        fail(f"{label}: raised {type(exc).__name__}({exc})")
    else:
        fail(f"{label}: no exception raised")


def run_generate(out: Path, *extra: str, env: dict | None = None) -> subprocess.CompletedProcess:
    cmd = [sys.executable, str(GENERATE), "--template", str(TEMPLATE), "--out", str(out), *extra]
    return subprocess.run(cmd, capture_output=True, text=True, env=env or os.environ.copy())


def run_install(*args: str) -> tuple[int, str]:
    """Call install-config's entry point with stdout/stderr captured."""
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        code = installer.main(list(args))
    return code, buffer.getvalue()


DEFAULTS = tomllib.loads(TEMPLATE.read_text(encoding="utf-8"))["skills"]["ignore"]
HOST_EXCLUSIONS = [f"~/.agents/skills/host-skill-{i:02d}" for i in range(11)] + [
    f"~/.claude/plugins/cache/host-plugin-{i:02d}/skills/inner" for i in range(11)
]


def host_config(ignore: list[str] | None = None) -> str:
    entries = "\n".join(f'    "{item}",' for item in (ignore or HOST_EXCLUSIONS))
    return textwrap.dedent(
        f"""\
        host_scalar = "top-level"

        [skills]
        ignore = [
        {entries}
        ]
        disabled = ["frontend-design", "host-disabled"]
        paths = ["~/host-skills"]
        server_skill_dirs = ["~/host-server-skills"]
        bundled_skill_dirs = ["~/host-bundled-skills"]
        extra_scalar = "host-owned"
        [skills.host_extra]
        keep = true

        [plugins]
        enabled = ["stale-name"]
        disabled = ["host-backup-restore"]
        paths = ["~/host-plugins"]

        [[marketplace.sources]]
        name = "my-team"
        git = "https://github.com/me/team-plugins.git"

        [host_only_table]
        note = "keep me"
        """
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="gbh-config-test.") as tmp:
        tmp_path = Path(tmp)
        host = tmp_path / "host.toml"
        host.write_text(host_config(), encoding="utf-8")

        # --- preservation: arrays, scalars, extra tables ----------------------
        out1 = tmp_path / "out1.toml"
        result = run_generate(out1, "--enabled", "a,b", "--preserve", str(host))
        check("preserve: generate exits 0", result.returncode == 0, result.stderr)
        cfg = tomllib.loads(out1.read_text(encoding="utf-8"))

        merged_ignore = cfg["skills"]["ignore"]
        check(
            "preserve: 22 host exclusions survive",
            all(item in merged_ignore for item in HOST_EXCLUSIONS),
            f"{len(merged_ignore)} entries",
        )
        check(
            "preserve: template defaults stay first",
            merged_ignore[:len(DEFAULTS)] == DEFAULTS,
            str(merged_ignore[:2]),
        )
        check(
            "preserve: ignore union is duplicate-free",
            len(merged_ignore) == len(set(merged_ignore)) == 24,
            str(len(merged_ignore)),
        )
        check(
            "preserve: skills.disabled unions host entry",
            cfg["skills"]["disabled"] == ["frontend-design", "host-disabled"],
            str(cfg["skills"]["disabled"]),
        )
        check(
            "preserve: skills.paths and dir lists survive",
            cfg["skills"]["paths"] == ["~/host-skills"]
            and cfg["skills"]["server_skill_dirs"] == ["~/host-server-skills"]
            and cfg["skills"]["bundled_skill_dirs"] == ["~/host-bundled-skills"],
        )
        check(
            "preserve: plugins.paths survives",
            cfg["plugins"]["paths"] == ["~/host-plugins"],
            str(cfg["plugins"]["paths"]),
        )
        check(
            "preserve: shared-table scalar survives",
            cfg["skills"].get("extra_scalar") == "host-owned",
        )
        check(
            "preserve: absent subtable inside shared table survives",
            cfg["skills"].get("host_extra") == {"keep": True},
        )
        check(
            "preserve: plugins.disabled survives beside template enabled",
            cfg["plugins"]["disabled"] == ["host-backup-restore"],
        )
        check(
            "preserve: enabled list stays template owned",
            cfg["plugins"]["enabled"] == ["a", "b"],
            str(cfg["plugins"]["enabled"]),
        )
        check(
            "preserve: host marketplace source survives",
            any(s.get("name") == "my-team" for s in cfg["marketplace"]["sources"]),
        )
        check(
            "preserve: host-only table survives",
            cfg["host_only_table"] == {"note": "keep me"},
        )
        check(
            "preserve: top-level host scalar survives",
            cfg.get("host_scalar") == "top-level",
        )

        empty_host = tmp_path / "empty-host.toml"
        empty_host.write_text("[empty_host]\n[skills.empty_child]\n", encoding="utf-8")
        empty_out = tmp_path / "empty-out.toml"
        result = run_generate(empty_out, "--preserve", str(empty_host))
        check("preserve: empty host tables render", result.returncode == 0, result.stderr)
        empty_cfg = tomllib.loads(empty_out.read_text(encoding="utf-8"))
        check("preserve: empty host table survives", empty_cfg.get("empty_host") == {})
        check("preserve: empty shared subtable survives", empty_cfg["skills"].get("empty_child") == {})

        # --- preservation: idempotency ---------------------------------------
        out2 = tmp_path / "out2.toml"
        result = run_generate(out2, "--enabled", "a,b", "--preserve", str(out1))
        check("preserve: second merge exits 0", result.returncode == 0, result.stderr)
        check(
            "preserve: repeated merge is byte-identical",
            out1.read_bytes() == out2.read_bytes(),
        )
        cfg2 = tomllib.loads(out2.read_text(encoding="utf-8"))
        check(
            "preserve: no duplicates after repeated merge",
            cfg2["skills"]["ignore"] == merged_ignore,
        )

        # --- preservation: template-owned values cannot be re-keyed ----------
        keyed = tmp_path / "keyed.toml"
        run_generate(keyed, "--hub-key", "hub", "--new-key", "new", "--context7-key", "ctx",
                     "--enabled", "a")
        env_only = tmp_path / "env-only.toml"
        result = run_generate(env_only, "--enabled", "a", "--preserve", str(keyed))
        check("template: env-only render over keyed host exits 0", result.returncode == 0,
              result.stderr)
        env_cfg = tomllib.loads(env_only.read_text(encoding="utf-8"))
        check(
            "template: dropped api_key is not resurrected from host",
            "api_key" not in env_cfg["model"]["kimi-k3"],
            str(sorted(env_cfg["model"]["kimi-k3"])),
        )
        check(
            "template: dropped context7 api-key arg is not resurrected",
            "--api-key" not in env_cfg["mcp_servers"]["context7"]["args"],
        )

        # --- preservation: host keys inside template-owned subtables ---------
        nested = tmp_path / "nested.toml"
        nested.write_text(
            "[model]\nhost_tuning = 1\n\n"
            '[model."gpt-5.6-sol"]\nmax_tokens_override = 42\n\n'
            "[model.deepseek-v4-flash.tools]\nhost_extra = true\n\n"
            "[subagents.models]\nextra-role = \"sonnet\"\n",
            encoding="utf-8",
        )
        nested_out = tmp_path / "nested-out.toml"
        result = run_generate(nested_out, "--enabled", "a", "--preserve", str(nested))
        check("nested: host keys in template subtables exit 0", result.returncode == 0,
              result.stderr)
        if result.returncode == 0:
            nested_cfg = tomllib.loads(nested_out.read_text(encoding="utf-8"))
            check(
                "nested: implicit parent table scalar survives",
                nested_cfg["model"].get("host_tuning") == 1,
            )
            check(
                "nested: scalar inside a quoted model table survives",
                nested_cfg["model"]["gpt-5.6-sol"].get("max_tokens_override") == 42,
            )
            check(
                "nested: host key inside a template subtable survives",
                nested_cfg["model"]["deepseek-v4-flash"]["tools"].get("host_extra") is True,
            )
            check(
                "nested: host role added to [subagents.models]",
                nested_cfg["subagents"]["models"].get("extra-role") == "sonnet",
            )
            check(
                "nested: template values in those tables still win",
                nested_cfg["model"]["deepseek-v4-flash"]["tools"]["deny"]
                == ["web_search", "web_fetch"],
            )
            nested_again = tmp_path / "nested-out2.toml"
            run_generate(nested_again, "--enabled", "a", "--preserve", str(nested_out))
            check(
                "nested: second merge is byte-identical",
                nested_out.read_bytes() == nested_again.read_bytes(),
            )

        # --- unsupported shapes fail closed ----------------------------------
        shape = tmp_path / "shape.toml"
        shape.write_text('[skills]\npaths = "~/not-an-array"\n', encoding="utf-8")
        sentinel = tmp_path / "sentinel.toml"
        sentinel.write_text("# untouched\n", encoding="utf-8")
        result = run_generate(sentinel, "--enabled", "a", "--preserve", str(shape))
        check("shape: scalar-for-array exits non-zero", result.returncode == 1, str(result.returncode))
        check(
            "shape: destination untouched",
            sentinel.read_text(encoding="utf-8") == "# untouched\n",
        )
        check("shape: error names the key", "skills.paths" in result.stderr, result.stderr)

        shape2 = tmp_path / "shape2.toml"
        shape2.write_text(
            '[plugins]\npaths = [{name = "x"}]\n', encoding="utf-8"
        )
        result = run_generate(sentinel, "--enabled", "a", "--preserve", str(shape2))
        check("shape: array-of-tables for string array exits 1", result.returncode == 1)

        # --- malformed host config fails closed ------------------------------
        bad = tmp_path / "bad.toml"
        bad.write_text('[skills\nignore = [\n', encoding="utf-8")
        result = run_generate(sentinel, "--enabled", "a", "--preserve", str(bad))
        check("malformed: exits 1", result.returncode == 1, str(result.returncode))
        check("malformed: error says malformed TOML", "malformed TOML" in result.stderr,
              result.stderr)
        check("malformed: destination untouched",
              sentinel.read_text(encoding="utf-8") == "# untouched\n")

        # --- parser unavailable is a distinct, fail-closed error -------------
        fake_pkg = tmp_path / "noctx"
        fake_pkg.mkdir()
        (fake_pkg / "tomllib.py").write_text(
            'raise ModuleNotFoundError("simulated: no tomllib")\n', encoding="utf-8"
        )
        env = os.environ.copy()
        env["PYTHONPATH"] = str(fake_pkg)
        result = run_generate(sentinel, "--enabled", "a", env=env)
        check("parser: unavailable parser exits 2", result.returncode == 2, str(result.returncode))
        check("parser: error names the missing parser", "no TOML parser" in result.stderr,
              result.stderr)
        check("parser: destination untouched",
              sentinel.read_text(encoding="utf-8") == "# untouched\n")

        # --- BOM and CRLF host configs parse ---------------------------------
        for label, payload in (
            ("BOM", b"\xef\xbb\xbf" + host_config().encode("utf-8")),
            ("CRLF", host_config().replace("\n", "\r\n").encode("utf-8")),
        ):
            alt = tmp_path / f"host-{label}.toml"
            alt.write_bytes(payload)
            alt_out = tmp_path / f"out-{label}.toml"
            result = run_generate(alt_out, "--enabled", "a", "--preserve", str(alt))
            check(f"encoding: {label} host config parses", result.returncode == 0,
                  result.stderr)
            if result.returncode == 0:
                alt_cfg = tomllib.loads(alt_out.read_text(encoding="utf-8"))
                check(
                    f"encoding: {label} host exclusions survive",
                    all(item in alt_cfg["skills"]["ignore"] for item in HOST_EXCLUSIONS),
                )

        # --- install-config: stale-hash conflict ------------------------------
        dest = tmp_path / "live" / "config.toml"
        dest.parent.mkdir()
        dest.write_text("# original\n", encoding="utf-8")
        stale_hash = installer.hash_path(dest)
        dest.write_text("# changed by someone else\n", encoding="utf-8")
        staged = tmp_path / "staged.toml"
        staged.write_text("[ui]\npermission_mode = \"plan\"\n", encoding="utf-8")
        code, _out = run_install(
            "--source", str(staged), "--dest", str(dest),
            "--expected-sha256", stale_hash, "--backup-dir", str(tmp_path / "backups"),
        )
        check("install: stale hash exits 3", code == 3, str(code))
        check("install: stale hash leaves destination alone",
              dest.read_text(encoding="utf-8") == "# changed by someone else\n")
        check("install: stale hash writes no backup",
              not (tmp_path / "backups").exists())

        for bad_hash in ("", "g" * 64, "abcd"):
            before = dest.read_bytes()
            code, _out = run_install(
                "--source", str(staged), "--dest", str(dest), "--expected-sha256", bad_hash,
            )
            check("install: malformed expected hash rejected", code == 1)
            check("install: malformed hash leaves destination", dest.read_bytes() == before)

        code, error = run_install("--hash", str(dest.parent))
        check("install: unreadable hash path returns clear error", code == 1 and "cannot hash" in error)
        blocked = tmp_path / "blocked-parent"
        blocked.write_text("file", encoding="utf-8")
        code, error = run_install("--source", str(staged), "--dest", str(blocked / "config.toml"))
        check("install: filesystem error returns 1", code == 1 and "ERROR" in error)

        # --- install-config: identical short-circuit -------------------------
        staged_text = staged.read_text(encoding="utf-8")
        dest.write_text(staged_text, encoding="utf-8")
        current_hash = installer.hash_path(dest)
        code, _out = run_install(
            "--source", str(staged), "--dest", str(dest), "--expected-sha256", current_hash,
        )
        check("install: identical content exits 0", code == 0, str(code))
        check("install: identical content is unchanged",
              dest.read_text(encoding="utf-8") == staged_text)

        # --- install-config: backup + permissions ----------------------------
        dest.write_text("# replaced\n", encoding="utf-8")
        current_hash = installer.hash_path(dest)
        os.chmod(dest, 0o600)
        backup_dir = tmp_path / "backups"
        code, _out = run_install(
            "--source", str(staged), "--dest", str(dest),
            "--expected-sha256", current_hash, "--backup-dir", str(backup_dir),
        )
        check("install: replace exits 0", code == 0, str(code))
        check("install: staged content installed",
              dest.read_text(encoding="utf-8") == staged.read_text(encoding="utf-8"))
        check("install: destination permissions preserved",
              stat.S_IMODE(dest.stat().st_mode) == 0o600,
              oct(stat.S_IMODE(dest.stat().st_mode)))
        backup = backup_dir / "config.toml"
        check("install: previous config backed up",
              backup.is_file() and backup.read_text(encoding="utf-8") == "# replaced\n")
        check("install: no temp files left behind",
              not list(dest.parent.glob(".*.tmp")), str(list(dest.parent.iterdir())))

        # --- install-config: symlinked destination ---------------------------
        real = tmp_path / "real-config.toml"
        real.write_text("[ui]\npermission_mode = \"plan\"\n", encoding="utf-8")
        link = tmp_path / "linked-config.toml"
        link.symlink_to(real)
        link_hash = installer.hash_path(link)
        new_staged = tmp_path / "staged2.toml"
        new_staged.write_text("[ui]\npermission_mode = \"always-approve\"\n", encoding="utf-8")
        code, _out = run_install(
            "--source", str(new_staged), "--dest", str(link),
            "--expected-sha256", link_hash, "--backup-dir", str(tmp_path / "backups2"),
        )
        check("install: symlink destination exits 0", code == 0, str(code))
        check("install: symlink is preserved", link.is_symlink())
        check("install: symlink target was rewritten",
              real.read_text(encoding="utf-8") == new_staged.read_text(encoding="utf-8"))
        check("install: symlink backup captured the target",
              (tmp_path / "backups2" / "real-config.toml").is_file())

        # --- install-config: unavailable parser exits 2 ----------------------
        no_parser = tmp_path / "noparser"
        no_parser.mkdir()
        (no_parser / "tomllib.py").write_text(
            'raise ModuleNotFoundError("simulated: no tomllib")\n', encoding="utf-8"
        )
        env = os.environ.copy()
        env["PYTHONPATH"] = str(no_parser)
        before = dest.read_bytes()
        result = subprocess.run(
            [sys.executable, str(INSTALL_CONFIG), "--source", str(staged),
             "--dest", str(dest)],
            capture_output=True, text=True, env=env,
        )
        check("install: unavailable parser exits 2", result.returncode == 2,
              str(result.returncode))
        check("install: unavailable parser leaves destination", dest.read_bytes() == before)

        # --- install-config: invalid staged source ---------------------------
        broken = tmp_path / "broken.toml"
        broken.write_text("[ui\n", encoding="utf-8")
        before = dest.read_bytes()
        code, _out = run_install("--source", str(broken), "--dest", str(dest))
        check("install: invalid staged TOML exits 1", code == 1, str(code))
        check("install: invalid staged TOML leaves destination", dest.read_bytes() == before)

        # --- install-config: absent destination ------------------------------
        fresh = tmp_path / "fresh" / "config.toml"
        fresh.parent.mkdir()
        code, _out = run_install(
            "--source", str(staged), "--dest", str(fresh), "--expected-sha256", "absent",
        )
        check("install: absent destination installs", code == 0, str(code))
        code, _out = run_install(
            "--source", str(staged), "--dest", str(fresh), "--expected-sha256", "absent",
        )
        check("install: 'absent' expectation rejects an existing file", code == 3, str(code))

    print(json.dumps({"passed": PASS, "failed": FAIL}))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
