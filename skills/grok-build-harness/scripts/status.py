#!/usr/bin/env python3
"""No-secrets grok-build-harness inventory.

Windows/Unix: python3 status.py --grok-home DIR --plugin-root DIR
install.sh --status is a thin wrapper. --docs-status stays one word.

Does not print API keys, env_key values, or secret tokens.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_PLUGIN_ROOT = HERE.parent
SPECS_PATH = DEFAULT_PLUGIN_ROOT / "assets" / "plugin-specs.json"
MERGE = HERE / "merge-agents.py"
ENGLISH_RULE = HERE / "english_rule.py"
CONTEXT_BUDGET = HERE / "context_budget.py"

CONTRACT_MEANING = {
    "match": "harness block equals installed assets",
    "drift": "block present but differs",
    "missing": "no AGENTS.md",
    "unmarked": "v0.2.0 unmarked contract",
    "absent": "file exists, no harness block",
}

REQUIRED_FILES = (
    "agents/grok-build-byok.md",
    "agents/scout.md",
    "agentrules.md",
    "AGENTS.md",
    "config.toml",
    ".grok-build-harness-stamp.json",
)

KEEP_WORKING_PREFIX = "- Keep working:"


def load_specs() -> list[dict]:
    return json.loads(SPECS_PATH.read_text(encoding="utf-8"))


def as_bash() -> int:
    for spec in load_specs():
        sys.stdout.write(
            "{name}|{source}|{skip_flag}\n".format(
                name=spec["name"],
                source=spec["source"],
                skip_flag=spec["skip_flag"],
            )
        )
    return 0


def plugin_version(plugin_root: Path) -> str:
    path = plugin_root / ".claude-plugin" / "plugin.json"
    try:
        return str(json.loads(path.read_text(encoding="utf-8")).get("version", "unknown"))
    except (OSError, json.JSONDecodeError):
        return "unknown"


def contract_status(plugin_root: Path, grok_home: Path) -> str:
    import importlib.util

    spec = importlib.util.spec_from_file_location("merge_agents", MERGE)
    if spec is None or spec.loader is None:
        return "missing"
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.status(str(plugin_root / "assets" / "AGENTS.md"), str(grok_home / "AGENTS.md"))


def keep_working_line(agents: Path) -> str | None:
    if not agents.is_file():
        return None
    for line in agents.read_text(encoding="utf-8").splitlines():
        if line.startswith(KEEP_WORKING_PREFIX):
            return line
    return None


def parse_config(path: Path) -> dict:
    out = {
        "agent": "missing",
        "plan_mode": "missing",
        "enabled": [],
        "has_config": path.is_file(),
    }
    if not path.is_file():
        return out
    text = path.read_text(encoding="utf-8")
    section = ""
    collecting = False
    enabled_buf: list[str] = []
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if collecting:
            enabled_buf.append(line)
            if "]" in line:
                collecting = False
            continue
        if line.startswith("enabled") and "=" in line and "[" in line:
            collecting = "]" not in line
            enabled_buf.append(line)
            if not collecting:
                pass
            continue
        if section == "agent" and line.startswith("name") and "=" in line:
            m = re.search(r'"([^"]*)"', line)
            if m:
                out["agent"] = m.group(1)
        if line.startswith("implement_via_subagents") and "=" in line:
            out["plan_mode"] = "true" if "true" in line.split("=", 1)[1] else "false"
    blob = " ".join(enabled_buf)
    out["enabled"] = re.findall(r'"([^"]+)"', blob)
    return out


def installed_plugin_names(grok_home: Path) -> set[str]:
    names: set[str] = set()
    root = grok_home / "installed-plugins"
    if not root.is_dir():
        return names
    manifests = (".claude-plugin", ".codex-plugin", ".cursor-plugin")
    for child in root.iterdir():
        if not child.is_dir():
            continue
        for plugin_dir in manifests:
            manifest = child / plugin_dir / "plugin.json"
            if not manifest.is_file():
                continue
            try:
                n = json.loads(manifest.read_text(encoding="utf-8")).get("name")
            except (OSError, json.JSONDecodeError):
                continue
            if n:
                names.add(str(n))
    return names


def plugin_present(grok_home: Path, name: str, installed: set[str] | None = None) -> bool:
    if installed is None:
        installed = installed_plugin_names(grok_home)
    return name in installed


def stamp_fields(path: Path) -> dict:
    if not path.is_file():
        return {"stamp": "missing", "stamp_grokgod": "missing", "stamp_installed_at": "missing"}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"stamp": "invalid", "stamp_grokgod": "missing", "stamp_installed_at": "missing"}
    grokgod = data.get("grokgod_detected")
    return {
        "stamp": str(data.get("plugin_version", "unknown")),
        "stamp_grokgod": "true" if grokgod is True else "false" if grokgod is False else "missing",
        "stamp_installed_at": str(data.get("installed_at", "missing")),
    }


def _load_mod(path: Path, name: str):
    import importlib.util

    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"{path.name} missing")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _english_mod():
    return _load_mod(ENGLISH_RULE, "english_rule")


def _context_mod():
    return _load_mod(CONTEXT_BUDGET, "context_budget")


def inventory(grok_home: Path, plugin_root: Path, user_home: Path | None = None) -> list[str]:
    lines: list[str] = []
    contract = contract_status(plugin_root, grok_home)
    lines.append(f"contract: {contract}")
    lines.append(f"contract_meaning: {CONTRACT_MEANING.get(contract, contract)}")
    lines.append(f"plugin: {plugin_version(plugin_root)}")
    lines.append(f"plugin_root: {plugin_root}")
    stamp = stamp_fields(grok_home / ".grok-build-harness-stamp.json")
    lines.append(f"stamp: {stamp['stamp']}")
    lines.append(f"stamp_grokgod: {stamp['stamp_grokgod']}")
    lines.append(f"stamp_installed_at: {stamp['stamp_installed_at']}")
    kw = keep_working_line(grok_home / "AGENTS.md")
    if kw:
        lines.append("keep_working: yes")
        lines.append(f"keep_working_line: {kw}")
    else:
        lines.append("keep_working: no")
    for rel in REQUIRED_FILES:
        exists = (grok_home / rel).is_file()
        lines.append(f"file: {'ok' if exists else 'missing'} {rel}")
    cfg = parse_config(grok_home / "config.toml")
    lines.append(f"agent: {cfg['agent']}")
    lines.append(f"plan_mode: {cfg['plan_mode']}")
    expected = [s["name"] for s in load_specs()]
    enabled = list(cfg["enabled"])
    enabled_set = set(enabled)
    installed = installed_plugin_names(grok_home)
    if not cfg["has_config"]:
        for name in expected:
            present = "present" if plugin_present(grok_home, name, installed) else "missing"
            lines.append(f"companion: {name} no-config {present}")
    else:
        for name in expected:
            state = "enabled" if name in enabled_set else "not-enabled"
            present = "present" if plugin_present(grok_home, name, installed) else "missing"
            lines.append(f"companion: {name} {state} {present}")
        for name in enabled:
            if name not in expected:
                present = "present" if plugin_present(grok_home, name, installed) else "missing"
                lines.append(f"companion: {name} extra {present}")
    eng = _english_mod()
    uh = user_home if user_home is not None else eng.default_user_home(grok_home)
    lines.extend(eng.inventory_lines(grok_home, uh, plugin_root))
    enabled_count = len(enabled) if cfg["has_config"] else 0
    lines.extend(_context_mod().inventory_lines(grok_home, uh, enabled_count))
    return lines


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv == ["--as-bash"]:
        return as_bash()
    parser = argparse.ArgumentParser(description="No-secrets grok-build-harness inventory")
    parser.add_argument("--grok-home", default=os.environ.get("GROK_HOME", str(Path.home() / ".grok")))
    parser.add_argument("--user-home", default="")
    parser.add_argument("--plugin-root", default=str(DEFAULT_PLUGIN_ROOT))
    parser.add_argument("--as-bash", action="store_true")
    args = parser.parse_args(argv)
    if args.as_bash:
        return as_bash()
    grok_home = Path(args.grok_home).expanduser()
    plugin_root = Path(args.plugin_root).expanduser()
    user_home = Path(args.user_home).expanduser() if args.user_home else None
    sys.stdout.write("\n".join(inventory(grok_home, plugin_root, user_home)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
