#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import shutil
import stat
from pathlib import Path

SCHEMA_URL = "https://json.schemastore.org/claude-code-settings.json"
SESSION_START_COMMAND = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/session-start.sh'
STOP_COMMAND = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/autopilot-keep-running.sh'
SESSION_START_TEMPLATE = Path("templates/hooks/session-start.sh")
STOP_TEMPLATE = Path("templates/hooks/autopilot-keep-running.sh")
RESET_TEMPLATE = Path("templates/commands/autopilot_reset.md")
ENV_DEFAULTS = {
    "AUTOPILOT_KEEP_RUNNING_DISABLED": "0",
    "CLAUDE_AUTOPILOT_MAX_TURNS": "20",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Install the repo-local Claude autopilot bundle into a target repository.",
    )
    parser.add_argument(
        "--target-repo",
        default=".",
        help="Target repository path. Defaults to the current working directory.",
    )
    return parser.parse_args()


def repo_root(target_repo: str) -> Path:
    return Path(target_repo).expanduser().resolve()


def skill_root() -> Path:
    return Path(__file__).resolve().parent.parent


def read_json(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"Expected top-level JSON object in {path}")
    return data


def ensure_object(parent: dict[str, object], key: str) -> dict[str, object]:
    value = parent.get(key)
    if isinstance(value, dict):
        return value
    new_value: dict[str, object] = {}
    parent[key] = new_value
    return new_value


def ensure_list(parent: dict[str, object], key: str) -> list[object]:
    value = parent.get(key)
    if isinstance(value, list):
        return value
    new_value: list[object] = []
    parent[key] = new_value
    return new_value


def normalize_hook_group(group: object) -> dict[str, object] | None:
    if not isinstance(group, dict):
        return None
    hooks = group.get("hooks")
    matcher = group.get("matcher", "")
    if not isinstance(hooks, list):
        hooks = []
    return {"matcher": matcher, "hooks": hooks}

def remove_command(hook_groups: list[object], command: str) -> list[object]:
    cleaned: list[object] = []
    for group in hook_groups:
        normalized = normalize_hook_group(group)
        if normalized is None:
            cleaned.append(group)
            continue
        hooks = normalized["hooks"]
        filtered_hooks = [
            hook
            for hook in hooks
            if not (isinstance(hook, dict) and hook.get("command") == command)
        ]
        if filtered_hooks:
            cleaned.append({"matcher": normalized["matcher"], "hooks": filtered_hooks})
    return cleaned


def canonical_hook_group(command: str, timeout: int) -> dict[str, object]:
    return {
        "matcher": "",
        "hooks": [
            {
                "command": command,
                "type": "command",
                "timeout": timeout,
            }
        ],
    }


def ensure_session_start(hooks: dict[str, object]) -> None:
    groups = ensure_list(hooks, "SessionStart")
    groups[:] = remove_command(groups, SESSION_START_COMMAND)
    groups.append(canonical_hook_group(SESSION_START_COMMAND, 5))


def ensure_stop_hook(hooks: dict[str, object]) -> None:
    groups = ensure_list(hooks, "Stop")
    groups[:] = remove_command(groups, STOP_COMMAND)
    groups.insert(0, canonical_hook_group(STOP_COMMAND, 10))


def ensure_env_defaults(settings: dict[str, object]) -> None:
    env = ensure_object(settings, "env")
    for key, value in ENV_DEFAULTS.items():
        if key not in env:
            env[key] = value


def patch_settings(settings_path: Path) -> None:
    settings = read_json(settings_path)
    if "$schema" not in settings:
        settings["$schema"] = SCHEMA_URL

    hooks = ensure_object(settings, "hooks")
    ensure_session_start(hooks)
    ensure_stop_hook(hooks)
    ensure_env_defaults(settings)

    settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")


def copy_template(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def make_executable(path: Path) -> None:
    current_mode = path.stat().st_mode
    path.chmod(current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def ensure_directories(repo: Path) -> tuple[Path, Path, Path]:
    claude_dir = repo / ".claude"
    hooks_dir = claude_dir / "hooks"
    commands_dir = claude_dir / "commands"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    commands_dir.mkdir(parents=True, exist_ok=True)
    return claude_dir, hooks_dir, commands_dir


def install(repo: Path) -> None:
    if not repo.exists() or not repo.is_dir():
        raise FileNotFoundError(f"Target repository does not exist: {repo}")

    root = skill_root()
    claude_dir, hooks_dir, commands_dir = ensure_directories(repo)

    copy_template(root / SESSION_START_TEMPLATE, hooks_dir / "session-start.sh")
    copy_template(root / STOP_TEMPLATE, hooks_dir / "autopilot-keep-running.sh")
    copy_template(root / RESET_TEMPLATE, commands_dir / "autopilot_reset.md")

    make_executable(hooks_dir / "session-start.sh")
    make_executable(hooks_dir / "autopilot-keep-running.sh")

    patch_settings(claude_dir / "settings.json")

    print(json.dumps(
        {
            "targetRepo": str(repo),
            "installedFiles": [
                str(hooks_dir / "session-start.sh"),
                str(hooks_dir / "autopilot-keep-running.sh"),
                str(commands_dir / "autopilot_reset.md"),
                str(claude_dir / "settings.json"),
            ],
        },
        indent=2,
    ))


def main() -> int:
    args = parse_args()
    try:
        install(repo_root(args.target_repo))
    except (FileNotFoundError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
