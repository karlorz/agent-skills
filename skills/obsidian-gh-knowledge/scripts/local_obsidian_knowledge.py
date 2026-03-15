#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


CONFIG_PATH = Path("~/.config/obsidian-gh-knowledge/config.json").expanduser()
DEFAULT_VAULT_DIR = Path("~/Documents/obsidian_vault").expanduser()
INBOX_DIR = "0️⃣-Inbox"
DRAFTS_DIR = "2️⃣-Drafts"
PROJECTS_ROOT = "5️⃣-Projects"
HELPER_WARNING = "Unable to find helper app"


def _expand_path(path: str) -> str:
    return os.path.abspath(os.path.expanduser(os.path.expandvars(path)))


def _die(message: str, exit_code: int = 2) -> None:
    print(message, file=sys.stderr)
    sys.exit(exit_code)


def _load_config() -> dict:
    if not CONFIG_PATH.exists():
        return {}
    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        _die(f"Failed to read config: {CONFIG_PATH}\n{exc}")
    if not isinstance(data, dict):
        _die(f"Config must contain a JSON object: {CONFIG_PATH}")
    return data


def _default_vault_dir(config: dict) -> Path:
    local_vault_path = config.get("local_vault_path")
    if isinstance(local_vault_path, str) and local_vault_path.strip():
        return Path(_expand_path(local_vault_path))
    return DEFAULT_VAULT_DIR


def _display_path(path: Path) -> str:
    home = Path.home()
    try:
        relative = path.resolve().relative_to(home.resolve())
    except ValueError:
        return str(path)
    if str(relative) == ".":
        return "~"
    return f"~/{relative}"


def _slugify(text: str) -> str:
    normalized = text.strip().lower()
    normalized = re.sub(r"[^a-z0-9]+", "-", normalized)
    normalized = re.sub(r"-{2,}", "-", normalized).strip("-")
    if not normalized:
        _die(f"Cannot derive a valid file name from: {text!r}")
    return normalized


def _normalize_note_name(name: str) -> str:
    normalized = name.strip()
    if normalized.lower().endswith(".md"):
        normalized = normalized[:-3]
    normalized = normalized.strip()
    if not normalized:
        _die(f"Cannot derive a valid note name from: {name!r}")
    return normalized


def _encode_cli_text(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")


def _clean_cli_stream(text: str) -> tuple[str, bool]:
    helper_warning = False
    cleaned_lines: list[str] = []
    for line in text.splitlines():
        if HELPER_WARNING in line:
            helper_warning = True
            continue
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines).strip(), helper_warning


def _run_process(cmd: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=False)


def _obsidian_binary() -> str:
    binary = shutil.which("obsidian")
    if not binary:
        _die(
            "Could not find `obsidian` in PATH.\n"
            "On macOS, enable the Obsidian CLI in Settings -> General -> Advanced -> Command line interface "
            "and ensure /Applications/Obsidian.app/Contents/MacOS is on PATH."
        )
    return binary


def _obsidian_command(vault_dir: Path, *args: str) -> tuple[str, list[str], bool]:
    _obsidian_binary()
    result = _run_process(["obsidian", *args], cwd=vault_dir)
    stdout, stdout_helper = _clean_cli_stream(result.stdout or "")
    stderr, stderr_helper = _clean_cli_stream(result.stderr or "")
    stderr_lines = [line for line in stderr.splitlines() if line.strip()]
    if result.returncode != 0:
        details = [part for part in [stdout, "\n".join(stderr_lines)] if part]
        joined = "\n".join(details)
        message = f"Obsidian command failed ({result.returncode}): obsidian {' '.join(args)}"
        if joined:
            message = f"{message}\n{joined}"
        _die(message, exit_code=result.returncode)
    return stdout, stderr_lines, stdout_helper or stderr_helper


def _int_output(value: str, *, label: str) -> int:
    try:
        return int(value.strip())
    except ValueError as exc:
        _die(f"Expected integer output for {label}, got: {value!r}\n{exc}")


def _list_project_names(vault_dir: Path, category: str) -> list[str]:
    project_root = vault_dir / PROJECTS_ROOT / category
    if not project_root.is_dir():
        return []
    return sorted(path.name for path in project_root.iterdir() if path.is_dir())


def _project_dir(vault_dir: Path, category: str, project: str) -> Path:
    return vault_dir / PROJECTS_ROOT / category / project


def _ensure_project_scope(vault_dir: Path, category: str, project: str) -> Path:
    project_dir = _project_dir(vault_dir, category, project)
    if not project_dir.is_dir():
        available = ", ".join(_list_project_names(vault_dir, category)) or "(none)"
        _die(
            f"Project folder not found: {project_dir}\n"
            f"Available {category} projects: {available}"
        )
    overview = project_dir / "_Overview.md"
    if not overview.exists():
        _die(f"Missing required project overview: {overview}")
    return project_dir


def _read_overview(vault_dir: Path, category: str, project: str) -> None:
    overview_path = _ensure_project_scope(vault_dir, category, project) / "_Overview.md"
    relative = overview_path.relative_to(vault_dir).as_posix()
    _obsidian_command(vault_dir, "read", f"path={relative}")


def _compose_note(title: str, *, intro: str | None = None, sources: list[str] | None = None) -> str:
    lines = [f"# {title}", "", "## TL;DR", "- Pending summary.", ""]
    if intro:
        lines.extend([intro.strip(), ""])
    lines.extend(["## Notes", "", "## Sources"])
    if sources:
        lines.extend([f"- {source}" for source in sources])
    else:
        lines.append("-")
    lines.append("")
    return "\n".join(lines)


def _sync_script() -> Path:
    return Path(__file__).with_name("local_vault_git_sync.py")


def _run_sync(vault_dir: Path, *, message: str | None, dry_run: bool) -> None:
    sync_script = _sync_script()
    cmd = [sys.executable, str(sync_script), "--vault-dir", str(vault_dir)]
    if message:
        cmd.extend(["--message", message])
    if dry_run:
        cmd.append("--dry-run")
    result = _run_process(cmd, cwd=vault_dir)
    if result.returncode != 0:
        details = "\n".join(part for part in [(result.stdout or "").strip(), (result.stderr or "").strip()] if part)
        message_text = f"Sync command failed ({result.returncode}): {' '.join(cmd)}"
        if details:
            message_text = f"{message_text}\n{details}"
        _die(message_text, exit_code=result.returncode)
    output = (result.stdout or "").strip()
    if output:
        print(output)


def _doctor(vault_dir: Path, *, json_output: bool) -> None:
    config = _load_config()
    help_output, help_stderr, helper_warning = _obsidian_command(vault_dir, "help")
    version_output, _, version_helper = _obsidian_command(vault_dir, "version")
    vault_name, _, name_helper = _obsidian_command(vault_dir, "vault", "info=name")
    vault_path, _, path_helper = _obsidian_command(vault_dir, "vault", "info=path")
    helper_warning = helper_warning or version_helper or name_helper or path_helper
    data = {
        "vault_dir": str(vault_dir),
        "vault_name": vault_name.strip() or config.get("vault_name") or vault_dir.name,
        "vault_path_reported_by_cli": vault_path.strip(),
        "config_path": str(CONFIG_PATH),
        "default_repo": config.get("default_repo"),
        "prefer_local": config.get("prefer_local"),
        "obsidian_binary": _obsidian_binary(),
        "cli_ready": bool(help_output),
        "version": version_output.strip(),
        "helper_warning_seen": helper_warning,
        "stderr": help_stderr,
    }
    if json_output:
        print(json.dumps(data, indent=2))
        return

    print(f"Vault: {data['vault_name']}")
    print(f"Path: {data['vault_dir']}")
    print(f"CLI path: {data['obsidian_binary']}")
    print(f"Version: {data['version']}")
    print(f"Config: {data['config_path']}")
    print(f"Default repo: {data['default_repo'] or '(unset)'}")
    print(f"Prefer local: {data['prefer_local']!r}")
    print("CLI ready: yes")
    if helper_warning:
        print("Warning: Obsidian printed macOS helper-app warnings, but CLI commands still completed successfully.")
    if help_stderr:
        print("CLI stderr:")
        for line in help_stderr:
            print(f"  {line}")


def _dashboard(vault_dir: Path, *, tags_limit: int, json_output: bool) -> None:
    stats = {
        "vault": (vault_dir.name),
        "path": str(vault_dir),
        "files": _int_output(_obsidian_command(vault_dir, "files", "total")[0], label="files"),
        "folders": _int_output(_obsidian_command(vault_dir, "folders", "total")[0], label="folders"),
        "inbox_notes": _int_output(
            _obsidian_command(vault_dir, "files", f"folder={INBOX_DIR}", "ext=md", "total")[0],
            label="inbox notes",
        ),
        "draft_notes": _int_output(
            _obsidian_command(vault_dir, "files", f"folder={DRAFTS_DIR}", "ext=md", "total")[0],
            label="draft notes",
        ),
        "orphans": _int_output(_obsidian_command(vault_dir, "orphans", "total")[0], label="orphans"),
        "deadends": _int_output(_obsidian_command(vault_dir, "deadends", "total")[0], label="deadends"),
        "unresolved_links": _int_output(
            _obsidian_command(vault_dir, "unresolved", "total")[0], label="unresolved links"
        ),
    }
    tags_output, _, helper_warning = _obsidian_command(vault_dir, "tags", "counts", "format=json")
    try:
        tags = json.loads(tags_output or "[]")
    except json.JSONDecodeError as exc:
        _die(f"Failed to parse `obsidian tags` JSON output.\n{exc}\n{tags_output}")
    top_tags = sorted(
        [
            {"tag": item.get("tag"), "count": int(item.get("count", 0))}
            for item in tags
            if isinstance(item, dict) and item.get("tag")
        ],
        key=lambda item: (-item["count"], item["tag"]),
    )[:tags_limit]
    stats["top_tags"] = top_tags
    stats["helper_warning_seen"] = helper_warning

    if json_output:
        print(json.dumps(stats, indent=2))
        return

    print(f"Vault: {stats['vault']}")
    print(f"Path: {stats['path']}")
    print(f"Files: {stats['files']}")
    print(f"Folders: {stats['folders']}")
    print(f"Inbox notes: {stats['inbox_notes']}")
    print(f"Draft notes: {stats['draft_notes']}")
    print(f"Orphans: {stats['orphans']}")
    print(f"Dead ends: {stats['deadends']}")
    print(f"Unresolved links: {stats['unresolved_links']}")
    print("Top tags:")
    if top_tags:
        for item in top_tags:
            print(f"  - {item['tag']} ({item['count']})")
    else:
        print("  - none")
    if helper_warning:
        print("Warning: Obsidian printed macOS helper-app warnings during the dashboard run.")


def _capture_note(
    vault_dir: Path,
    *,
    title: str,
    folder: str,
    name: str | None,
    body: str | None,
    overwrite: bool,
    sync: bool,
    dry_run: bool,
) -> None:
    target_folder = vault_dir / folder
    if not target_folder.is_dir():
        _die(f"Target folder does not exist: {target_folder}")
    file_name = _normalize_note_name(name) if name else _slugify(title)
    content = _compose_note(title, intro=body)
    cmd = ["create", f"name={file_name}", f"path={folder}", f"content={_encode_cli_text(content)}"]
    if overwrite:
        cmd.append("overwrite")
    relative_path = f"{folder}/{file_name}.md"
    if dry_run:
        print(f"Would create: {relative_path}")
        return
    _obsidian_command(vault_dir, *cmd)
    print(f"Created: {relative_path}")
    if sync:
        _run_sync(vault_dir, message=f"Add note: {file_name}", dry_run=False)


def _project_note(
    vault_dir: Path,
    *,
    project: str,
    category: str,
    title: str,
    name: str | None,
    body: str | None,
    source: list[str],
    overwrite: bool,
    sync: bool,
    dry_run: bool,
) -> None:
    project_dir = _ensure_project_scope(vault_dir, category, project)
    _read_overview(vault_dir, category, project)
    file_name = _normalize_note_name(name) if name else _slugify(title)
    relative_folder = project_dir.relative_to(vault_dir).as_posix()
    relative_path = f"{relative_folder}/{file_name}.md"
    content = _compose_note(
        title,
        intro=body or f"Project note for `{project}`.",
        sources=source,
    )
    cmd = ["create", f"name={file_name}", f"path={relative_folder}", f"content={_encode_cli_text(content)}"]
    if overwrite:
        cmd.append("overwrite")
    if dry_run:
        print(f"Would create: {relative_path}")
        return
    _obsidian_command(vault_dir, *cmd)
    print(f"Created: {relative_path}")
    if sync:
        _run_sync(vault_dir, message=f"Add project note: {file_name}", dry_run=False)


def _organize_note(
    vault_dir: Path,
    *,
    source: str,
    project: str,
    category: str,
    name: str | None,
    keep_name: bool,
    subdir: str | None,
    sync: bool,
    dry_run: bool,
) -> None:
    project_dir = _ensure_project_scope(vault_dir, category, project)
    _read_overview(vault_dir, category, project)
    source_path = Path(source)
    source_abs = vault_dir / source_path
    if not source_abs.exists():
        _die(f"Source note does not exist: {source_abs}")
    if not source_abs.is_file():
        _die(f"Source path is not a file: {source_abs}")
    extension = source_path.suffix or ".md"
    if keep_name:
        base_name = _normalize_note_name(source_path.name)
    elif name:
        base_name = _slugify(_normalize_note_name(name))
    else:
        base_name = _slugify(source_path.stem)
    relative_folder = project_dir.relative_to(vault_dir)
    if subdir:
        relative_folder = relative_folder / subdir
    destination = (relative_folder / f"{base_name}{extension}").as_posix()
    if dry_run:
        print(f"Would move: {source} -> {destination}")
        return
    _obsidian_command(vault_dir, "move", f"path={source}", f"to={destination}")
    print(f"Moved: {source} -> {destination}")
    if sync:
        _run_sync(vault_dir, message=f"Organize note into {project}: {base_name}", dry_run=False)


def _sync(vault_dir: Path, args: argparse.Namespace) -> None:
    _run_sync(vault_dir, message=args.message, dry_run=args.dry_run)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="High-level local Obsidian CLI workflows for managing a local vault on macOS."
    )
    parser.add_argument(
        "--vault-dir",
        default=None,
        help="Override the local vault directory. Default: config local_vault_path, else ~/Documents/obsidian_vault",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    doctor_parser = subparsers.add_parser("doctor", help="Check local Obsidian CLI readiness")
    doctor_parser.add_argument("--json", action="store_true", help="Output JSON")

    dashboard_parser = subparsers.add_parser("dashboard", help="Show vault organization health")
    dashboard_parser.add_argument("--json", action="store_true", help="Output JSON")
    dashboard_parser.add_argument("--tags-limit", type=int, default=10, help="Number of top tags to show")

    capture_parser = subparsers.add_parser("capture", help="Create a new note in Inbox or another folder")
    capture_parser.add_argument("title", help="Human title for the note")
    capture_parser.add_argument("--folder", default=INBOX_DIR, help=f"Target folder. Default: {INBOX_DIR}")
    capture_parser.add_argument("--name", default=None, help="Optional file name override")
    capture_parser.add_argument("--body", default=None, help="Optional intro paragraph")
    capture_parser.add_argument("--overwrite", action="store_true", help="Overwrite an existing note")
    capture_parser.add_argument("--sync", action="store_true", help="Run git sync after creation")
    capture_parser.add_argument("--dry-run", action="store_true", help="Print the planned path only")

    project_note_parser = subparsers.add_parser("project-note", help="Create a note inside a project folder")
    project_note_parser.add_argument("project", help="Project folder name under 5️⃣-Projects/<category>/")
    project_note_parser.add_argument("title", help="Human title for the note")
    project_note_parser.add_argument("--category", default="GitHub", help="Project category folder")
    project_note_parser.add_argument("--name", default=None, help="Optional file name override")
    project_note_parser.add_argument("--body", default=None, help="Optional intro paragraph")
    project_note_parser.add_argument(
        "--source",
        action="append",
        default=[],
        help="External source URL or citation line to seed the Sources section",
    )
    project_note_parser.add_argument("--overwrite", action="store_true", help="Overwrite an existing note")
    project_note_parser.add_argument("--sync", action="store_true", help="Run git sync after creation")
    project_note_parser.add_argument("--dry-run", action="store_true", help="Print the planned path only")

    organize_parser = subparsers.add_parser(
        "organize",
        help="Move a note into a project folder using Obsidian so wikilinks stay in sync",
    )
    organize_parser.add_argument("source", help="Source note path relative to the vault root")
    organize_parser.add_argument("project", help="Target project folder name")
    organize_parser.add_argument("--category", default="GitHub", help="Project category folder")
    organize_parser.add_argument("--name", default=None, help="Optional destination base name")
    organize_parser.add_argument("--keep-name", action="store_true", help="Preserve the original base name")
    organize_parser.add_argument("--subdir", default=None, help="Optional subdirectory inside the project folder")
    organize_parser.add_argument("--sync", action="store_true", help="Run git sync after moving the note")
    organize_parser.add_argument("--dry-run", action="store_true", help="Print the planned move only")

    sync_parser = subparsers.add_parser("sync", help="Run the local vault git sync helper")
    sync_parser.add_argument("--message", default=None, help="Commit message override")
    sync_parser.add_argument("--dry-run", action="store_true", help="Print git commands without changing anything")

    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    config = _load_config()
    vault_dir = Path(_expand_path(args.vault_dir)) if args.vault_dir else _default_vault_dir(config)
    if not vault_dir.is_dir():
        _die(f"Vault directory does not exist: {_display_path(vault_dir)}")

    if args.command == "doctor":
        _doctor(vault_dir, json_output=args.json)
        return

    if args.command == "dashboard":
        _dashboard(vault_dir, tags_limit=args.tags_limit, json_output=args.json)
        return

    if args.command == "capture":
        _capture_note(
            vault_dir,
            title=args.title,
            folder=args.folder,
            name=args.name,
            body=args.body,
            overwrite=args.overwrite,
            sync=args.sync,
            dry_run=args.dry_run,
        )
        return

    if args.command == "project-note":
        _project_note(
            vault_dir,
            project=args.project,
            category=args.category,
            title=args.title,
            name=args.name,
            body=args.body,
            source=args.source,
            overwrite=args.overwrite,
            sync=args.sync,
            dry_run=args.dry_run,
        )
        return

    if args.command == "organize":
        _organize_note(
            vault_dir,
            source=args.source,
            project=args.project,
            category=args.category,
            name=args.name,
            keep_name=args.keep_name,
            subdir=args.subdir,
            sync=args.sync,
            dry_run=args.dry_run,
        )
        return

    if args.command == "sync":
        _sync(vault_dir, args)
        return

    _die(f"Unknown command: {args.command}", exit_code=1)


if __name__ == "__main__":
    main()
