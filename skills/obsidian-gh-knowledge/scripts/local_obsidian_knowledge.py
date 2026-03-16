#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    yaml = None


CONFIG_PATH = Path("~/.config/obsidian-gh-knowledge/config.json").expanduser()
DEFAULT_VAULT_DIR = Path("~/Documents/obsidian_vault").expanduser()
INBOX_DIR = "0️⃣-Inbox"
DRAFTS_DIR = "2️⃣-Drafts"
PROJECTS_ROOT = "5️⃣-Projects"
HELPER_WARNING = "Unable to find helper app"
REQUIRED_FOLDERS = (
    INBOX_DIR,
    "1️⃣-Index",
    DRAFTS_DIR,
    "3️⃣-Plugins",
    "4️⃣-Attachments",
    PROJECTS_ROOT,
    "assets",
    "100-Templates",
)
AUDIT_SKIP_DIRS = {
    ".git",
    ".obsidian",
    ".sisyphus",
    ".agent",
    ".venv",
    ".venv_xlsx",
    "assets",
    "4️⃣-Attachments",
    "archive",
    "_archive",
    "node_modules",
}
TLDR_SKIP_TOP_LEVEL_DIRS = {
    "agent-skills",
    "help_obsidian_md",
}
TLDR_SKIP_FILE_NAMES = {
    "README.md",
    "AGENTS.md",
    "CLAUDE.md",
    "_Overview.md",
}
STRUCTURE_REPORT_DEFAULT = "1️⃣-Index/vault-structure-cleanup-report.md"
PROJECT_DIR_SKIP_NAMES = {
    "archive",
    "_archive",
}
TLDR_PATTERN = re.compile(r"^\s*##\s+TL;DR\s*$", re.IGNORECASE)
WIKILINK_PATTERN = re.compile(r"!?\[\[([^\]]+)\]\]")
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


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
    if "/" in normalized or "\\" in normalized:
        _die(f"Note name must not contain path separators: {name!r}")
    if normalized in {".", ".."}:
        _die(f"Note name must not be '.' or '..': {name!r}")
    if not normalized:
        _die(f"Cannot derive a valid note name from: {name!r}")
    return normalized


def _normalize_relative_path(value: str, *, label: str) -> Path:
    raw = value.strip().replace("\\", "/")
    if not raw:
        _die(f"{label} cannot be empty.")
    candidate = Path(raw)
    if candidate.is_absolute():
        _die(f"{label} must be relative to the vault root: {value!r}")
    if any(part in {"", ".", ".."} for part in candidate.parts):
        _die(f"{label} must not contain '.' or '..': {value!r}")
    return Path(*candidate.parts)


def _resolve_vault_path(
    vault_dir: Path,
    value: str,
    *,
    label: str,
    must_exist: bool = False,
    expect_directory: bool | None = None,
) -> tuple[Path, str]:
    normalized = _normalize_relative_path(value, label=label)
    resolved_vault = vault_dir.resolve()
    resolved_path = (resolved_vault / normalized).resolve()
    try:
        resolved_path.relative_to(resolved_vault)
    except ValueError:
        _die(f"{label} escapes the vault root: {value!r}")

    if must_exist and not resolved_path.exists():
        _die(f"{label} does not exist: {resolved_path}")
    if expect_directory is True and not resolved_path.is_dir():
        _die(f"{label} is not a directory: {resolved_path}")
    if expect_directory is False and not resolved_path.is_file():
        _die(f"{label} is not a file: {resolved_path}")

    return resolved_path, normalized.as_posix()


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


def _pluralize(count: int, singular: str, plural: str | None = None) -> str:
    if count == 1:
        return singular
    return plural or f"{singular}s"


def _be_verb(count: int) -> str:
    return "is" if count == 1 else "are"


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


def _json_command(vault_dir: Path, *args: str, label: str) -> tuple[object, bool]:
    output, _, helper_warning = _obsidian_command(vault_dir, *args)
    try:
        data = json.loads(output or "[]")
    except json.JSONDecodeError as exc:
        _die(f"Failed to parse JSON output for {label}.\n{exc}\n{output}")
    return data, helper_warning


def _should_skip_audit_path(relative_path: Path) -> bool:
    for part in relative_path.parts[:-1]:
        if part.startswith(".") or part in AUDIT_SKIP_DIRS:
            return True
    return False


def _should_check_tldr(relative_path: Path) -> bool:
    if _should_skip_audit_path(relative_path):
        return False
    if relative_path.name in TLDR_SKIP_FILE_NAMES:
        return False
    if relative_path.parts and relative_path.parts[0] in TLDR_SKIP_TOP_LEVEL_DIRS:
        return False
    return True


def _iter_audit_markdown_files(vault_dir: Path) -> list[Path]:
    markdown_files: list[Path] = []
    for path in vault_dir.rglob("*.md"):
        if not path.is_file():
            continue
        relative_path = path.relative_to(vault_dir)
        if _should_skip_audit_path(relative_path):
            continue
        markdown_files.append(relative_path)
    return sorted(markdown_files)


def _project_directories(vault_dir: Path) -> list[Path]:
    projects_root = vault_dir / PROJECTS_ROOT
    if not projects_root.is_dir():
        return []

    project_dirs: list[Path] = []
    for category_dir in sorted(path for path in projects_root.iterdir() if path.is_dir()):
        if any(path.is_file() and path.suffix == ".md" for path in category_dir.iterdir()):
            project_dirs.append(category_dir.relative_to(vault_dir))
        for project_dir in sorted(path for path in category_dir.iterdir() if path.is_dir()):
            if project_dir.name.lower() in PROJECT_DIR_SKIP_NAMES or project_dir.name.startswith("."):
                continue
            project_dirs.append(project_dir.relative_to(vault_dir))
    return project_dirs


def _extract_frontmatter(lines: list[str]) -> tuple[str | None, int, str | None]:
    if not lines or lines[0].strip() != "---":
        return None, 0, None

    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "\n".join(lines[1:index]), index + 1, None

    return None, 0, "Unterminated frontmatter block"


def _find_tldr_line(lines: list[str], *, start_index: int) -> int | None:
    for index in range(start_index, len(lines)):
        if TLDR_PATTERN.match(lines[index]):
            return index + 1
    return None


def _render_sample(item: object) -> str:
    if isinstance(item, str):
        return item
    if isinstance(item, dict):
        if "path" in item and "error" in item:
            return f"{item['path']}: {item['error']}"
        if "path" in item and "line" in item:
            return f"{item['path']}: line {item['line']}"
    return str(item)


def _print_samples(title: str, items: list[object], *, limit: int) -> None:
    print(f"{title}: {len(items)}")
    if not items:
        print("  - none")
        return
    for item in items[:limit]:
        print(f"  - {_render_sample(item)}")
    remaining = len(items) - limit
    if remaining > 0:
        print(f"  - ... {remaining} more")


def _missing_tldr_paths(vault_dir: Path) -> list[str]:
    missing_tldr: list[str] = []
    for relative_path in _iter_audit_markdown_files(vault_dir):
        if not _should_check_tldr(relative_path):
            continue
        path = vault_dir / relative_path
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        lines = text.splitlines()
        _, content_start_index, frontmatter_error = _extract_frontmatter(lines)
        if frontmatter_error:
            continue
        if _find_tldr_line(lines, start_index=content_start_index) is None:
            missing_tldr.append(relative_path.as_posix())
    return missing_tldr


def _insert_tldr(text: str) -> str:
    lines = text.splitlines()
    _, content_start_index, _ = _extract_frontmatter(lines)

    insert_at: int | None = None
    for index in range(content_start_index, len(lines)):
        if re.match(r"^\s*##\s+", lines[index]):
            insert_at = index
            break

    if insert_at is None:
        for index in range(content_start_index, len(lines)):
            if lines[index].strip():
                if lines[index].startswith("# "):
                    insert_at = index + 1
                else:
                    insert_at = index
                break

    if insert_at is None:
        insert_at = len(lines)

    before = lines[:insert_at]
    after = lines[insert_at:]
    while after and not after[0].strip():
        after = after[1:]
    if before and before[-1].strip():
        before.append("")
    before.extend(["## TL;DR", "- Pending summary.", ""])
    before.extend(after)
    new_text = "\n".join(before).rstrip() + "\n"
    return new_text


def _collapse_relative_link(base: Path, target: str) -> Path | None:
    combined = base / Path(target)
    parts: list[str] = []
    for part in combined.parts:
        if part in {"", "."}:
            continue
        if part == "..":
            if not parts:
                return None
            parts.pop()
            continue
        parts.append(part)
    if not parts:
        return None
    return Path(*parts)


def _structure_note_link(relative_path: Path, *, display: str | None = None) -> str:
    target = relative_path.with_suffix("").as_posix()
    label = display or relative_path.stem
    return f"[[{target}|{label}]]"


def _structure_overview_path(relative_path: Path, note_paths: set[str]) -> Path | None:
    for parent in [relative_path.parent, *relative_path.parents]:
        if str(parent) in {"", "."}:
            continue
        candidate = parent / "_Overview.md"
        if candidate.as_posix() in note_paths:
            return candidate
    return None


def _resolve_note_target(
    source_relative: Path,
    target: str,
    *,
    note_paths: set[str],
    root_path_map: dict[str, Path],
    basename_map: dict[str, list[Path]],
) -> Path | None:
    cleaned = target.strip().replace("\\", "/")
    if not cleaned:
        return None
    cleaned = cleaned.split("|", 1)[0].strip()
    cleaned = cleaned.split("#", 1)[0].strip()
    cleaned = cleaned.split("^", 1)[0].strip()
    if not cleaned:
        return None
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", cleaned):
        return None
    if cleaned.startswith(("mailto:", "#")):
        return None

    extension = Path(cleaned).suffix.lower()
    if extension and extension != ".md":
        return None

    candidates: list[Path] = []
    direct_keys: list[str] = []
    if cleaned.startswith("/"):
        direct_keys.append(cleaned.lstrip("/"))
    elif cleaned.startswith(("./", "../")):
        resolved = _collapse_relative_link(source_relative.parent, cleaned)
        if resolved is not None:
            direct_keys.append(resolved.as_posix())
    elif "/" in cleaned:
        direct_keys.append(cleaned)

    for key in direct_keys:
        normalized = key[:-3] if key.lower().endswith(".md") else key
        if key in root_path_map:
            candidates.append(root_path_map[key])
        md_key = f"{normalized}.md"
        if md_key in root_path_map:
            candidates.append(root_path_map[md_key])

    if not candidates:
        basename = Path(cleaned).stem if extension == ".md" else cleaned
        basename_key = basename.lower()
        candidates = list(basename_map.get(basename_key, []))

    if not candidates:
        return None

    unique_candidates = sorted({candidate.as_posix(): candidate for candidate in candidates}.values(), key=lambda p: (
        p.parent != source_relative.parent,
        p.parts[:2] != source_relative.parts[:2],
        len(p.parts),
        p.as_posix(),
    ))
    resolved = unique_candidates[0]
    if resolved.as_posix() not in note_paths or resolved == source_relative:
        return None
    return resolved


def _extract_note_targets(
    text: str,
    source_relative: Path,
    *,
    note_paths: set[str],
    root_path_map: dict[str, Path],
    basename_map: dict[str, list[Path]],
) -> set[Path]:
    targets: set[Path] = set()
    for match in WIKILINK_PATTERN.finditer(text):
        resolved = _resolve_note_target(
            source_relative,
            match.group(1),
            note_paths=note_paths,
            root_path_map=root_path_map,
            basename_map=basename_map,
        )
        if resolved is not None and resolved != source_relative:
            targets.add(resolved)

    for match in MARKDOWN_LINK_PATTERN.finditer(text):
        resolved = _resolve_note_target(
            source_relative,
            match.group(1),
            note_paths=note_paths,
            root_path_map=root_path_map,
            basename_map=basename_map,
        )
        if resolved is not None and resolved != source_relative:
            targets.add(resolved)
    return targets


def _folder_counts(paths: list[Path]) -> list[dict[str, object]]:
    counts = Counter(path.parent.as_posix() for path in paths)
    return [
        {"folder": folder, "count": count}
        for folder, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    ]


def _structure_report_data(vault_dir: Path, *, output_relative: Path, limit: int, hotspot_limit: int) -> dict:
    note_paths_list = [
        relative_path
        for relative_path in _iter_audit_markdown_files(vault_dir)
        if relative_path != output_relative
    ]
    note_paths = {path.as_posix() for path in note_paths_list}
    root_path_map = {path.as_posix(): path for path in note_paths_list}
    basename_map: dict[str, list[Path]] = defaultdict(list)
    for path in note_paths_list:
        basename_map[path.stem.lower()].append(path)

    outgoing_map: dict[Path, set[Path]] = {}
    inbound_map: dict[Path, set[Path]] = {path: set() for path in note_paths_list}
    read_errors: list[dict[str, str]] = []

    for relative_path in note_paths_list:
        path = vault_dir / relative_path
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            read_errors.append({"path": relative_path.as_posix(), "error": str(exc)})
            outgoing_map[relative_path] = set()
            continue
        targets = _extract_note_targets(
            text,
            relative_path,
            note_paths=note_paths,
            root_path_map=root_path_map,
            basename_map=basename_map,
        )
        outgoing_map[relative_path] = targets
        for target in targets:
            inbound_map.setdefault(target, set()).add(relative_path)

    orphans = sorted(path for path in note_paths_list if not inbound_map.get(path))
    deadends = sorted(path for path in note_paths_list if not outgoing_map.get(path))
    isolated = sorted(path for path in note_paths_list if path in orphans and path in deadends)

    def _sample_rows(paths: list[Path]) -> list[dict[str, str]]:
        rows: list[dict[str, str]] = []
        for path in paths[:limit]:
            overview = _structure_overview_path(path, note_paths)
            rows.append(
                {
                    "path": path.as_posix(),
                    "folder": path.parent.as_posix(),
                    "overview": overview.as_posix() if overview else "",
                    "note_link": _structure_note_link(path),
                    "overview_link": _structure_note_link(overview, display="Overview") if overview else "—",
                }
            )
        return rows

    orphan_hotspots = _folder_counts(orphans)[:hotspot_limit]
    deadend_hotspots = _folder_counts(deadends)[:hotspot_limit]
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    return {
        "generated_at": timestamp,
        "scope": {
            "notes_analyzed": len(note_paths_list),
            "output_path": output_relative.as_posix(),
            "limit": limit,
            "hotspot_limit": hotspot_limit,
        },
        "counts": {
            "orphans": len(orphans),
            "deadends": len(deadends),
            "isolated": len(isolated),
        },
        "read_errors": read_errors,
        "orphans": {
            "hotspots": orphan_hotspots,
            "sample": _sample_rows(orphans),
        },
        "deadends": {
            "hotspots": deadend_hotspots,
            "sample": _sample_rows(deadends),
        },
        "isolated": {
            "sample": _sample_rows(isolated),
        },
    }


def _structure_report_markdown(data: dict) -> str:
    counts = data["counts"]
    scope = data["scope"]
    orphan_hotspots = data["orphans"]["hotspots"]
    deadend_hotspots = data["deadends"]["hotspots"]
    isolated_sample = data["isolated"]["sample"]
    orphan_sample = data["orphans"]["sample"]
    deadend_sample = data["deadends"]["sample"]

    lines = [
        "# Vault Structure Cleanup Report",
        "",
        "## TL;DR",
        f"- Active-scope note graph analyzed **{scope['notes_analyzed']}** markdown notes.",
        f"- **{counts['isolated']}** notes are fully isolated, **{counts['orphans']}** have no inbound links, and **{counts['deadends']}** have no outbound links.",
        f"- Report generated on **{data['generated_at']}** and excludes archive, attachment, hidden, and generated-report paths.",
        "",
        "## Scope",
        "- Excludes `archive`, `_archive`, attachments/assets, hidden/system folders, and the generated cleanup report itself.",
        "- Uses local Markdown link parsing for wikilinks and internal markdown paths, not the unstable live Obsidian orphan/dead-end list commands.",
        "",
        "## Hotspots",
        "",
        "### Orphan Hotspots",
        "| Folder | Count |",
        "| --- | ---: |",
    ]
    if orphan_hotspots:
        for item in orphan_hotspots:
            lines.append(f"| `{item['folder']}` | {item['count']} |")
    else:
        lines.append("| none | 0 |")

    lines.extend([
        "",
        "### Dead-End Hotspots",
        "| Folder | Count |",
        "| --- | ---: |",
    ])
    if deadend_hotspots:
        for item in deadend_hotspots:
            lines.append(f"| `{item['folder']}` | {item['count']} |")
    else:
        lines.append("| none | 0 |")

    def _append_rows(title: str, rows: list[dict[str, str]]) -> None:
        lines.extend([
            "",
            f"## {title}",
            "| Note | Folder | Suggested Overview |",
            "| --- | --- | --- |",
        ])
        if rows:
            for row in rows:
                lines.append(f"| {row['note_link']} | `{row['folder']}` | {row['overview_link']} |")
        else:
            lines.append("| none | — | — |")

    _append_rows("Priority Isolated Notes", isolated_sample)
    _append_rows("Orphan Note Samples", orphan_sample)
    _append_rows("Dead-End Note Samples", deadend_sample)

    lines.extend([
        "",
        "## Suggested Actions",
        "- Add isolated and orphan notes to the nearest `_Overview.md` first; that gives them an inbound anchor without restructuring the whole vault.",
        "- Add a small `## Related` section to dead-end notes with the local `_Overview.md` and one or two sibling notes.",
        "- Re-run `structure-report` after each cleanup batch instead of relying on vault-wide totals alone.",
        "",
    ])

    return "\n".join(lines)


def _doctor_data(vault_dir: Path) -> dict:
    config = _load_config()
    help_output, help_stderr, helper_warning = _obsidian_command(vault_dir, "help")
    version_output, _, version_helper = _obsidian_command(vault_dir, "version")
    vault_name, _, name_helper = _obsidian_command(vault_dir, "vault", "info=name")
    vault_path, _, path_helper = _obsidian_command(vault_dir, "vault", "info=path")
    helper_warning = helper_warning or version_helper or name_helper or path_helper
    return {
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


def _doctor(vault_dir: Path, *, json_output: bool) -> None:
    data = _doctor_data(vault_dir)
    if json_output:
        print(json.dumps(data, indent=2))
        return

    helper_warning = bool(data["helper_warning_seen"])
    help_stderr = data["stderr"]
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


def _dashboard_data(vault_dir: Path, *, tags_limit: int) -> dict:
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
    tags, helper_warning = _json_command(vault_dir, "tags", "counts", "format=json", label="obsidian tags")
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
    return stats


def _dashboard(vault_dir: Path, *, tags_limit: int, json_output: bool) -> None:
    stats = _dashboard_data(vault_dir, tags_limit=tags_limit)

    if json_output:
        print(json.dumps(stats, indent=2))
        return

    top_tags = stats["top_tags"]
    helper_warning = bool(stats["helper_warning_seen"])
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


def _review(vault_dir: Path, *, json_output: bool, tags_limit: int, unresolved_limit: int, recent_limit: int) -> None:
    doctor = _doctor_data(vault_dir)
    dashboard = _dashboard_data(vault_dir, tags_limit=tags_limit)
    todo_tasks = _int_output(_obsidian_command(vault_dir, "tasks", "todo", "total")[0], label="todo tasks")
    done_tasks = _int_output(_obsidian_command(vault_dir, "tasks", "done", "total")[0], label="done tasks")
    recent_output, _, recent_helper = _obsidian_command(vault_dir, "recents")
    unresolved_data, unresolved_helper = _json_command(
        vault_dir,
        "unresolved",
        "counts",
        "format=json",
        label="obsidian unresolved",
    )

    recent_files = [line.strip() for line in recent_output.splitlines() if line.strip()][:recent_limit]
    top_unresolved = sorted(
        [
            {"link": item.get("link"), "count": int(item.get("count", 0))}
            for item in unresolved_data
            if isinstance(item, dict) and item.get("link")
        ],
        key=lambda item: (-item["count"], item["link"]),
    )[:unresolved_limit]

    review = {
        "doctor": doctor,
        "dashboard": dashboard,
        "tasks": {
            "todo": todo_tasks,
            "done": done_tasks,
        },
        "recent_files": recent_files,
        "top_unresolved_links": top_unresolved,
        "helper_warning_seen": bool(
            doctor["helper_warning_seen"] or dashboard["helper_warning_seen"] or recent_helper or unresolved_helper
        ),
    }
    flags: list[str] = []
    if dashboard["unresolved_links"] > 0:
        flags.append(
            f"{dashboard['unresolved_links']} unresolved {_pluralize(dashboard['unresolved_links'], 'link')} need cleanup."
        )
    if dashboard["inbox_notes"] > 0:
        flags.append(
            f"{dashboard['inbox_notes']} inbox {_pluralize(dashboard['inbox_notes'], 'note')} {_be_verb(dashboard['inbox_notes'])} waiting for triage."
        )
    if dashboard["draft_notes"] > 0:
        flags.append(
            f"{dashboard['draft_notes']} draft {_pluralize(dashboard['draft_notes'], 'note')} {_be_verb(dashboard['draft_notes'])} still unorganized."
        )
    if dashboard["orphans"] > 0:
        flags.append(
            f"{dashboard['orphans']} {_pluralize(dashboard['orphans'], 'note')} {_be_verb(dashboard['orphans'])} missing inbound links."
        )
    review["flags"] = flags

    if json_output:
        print(json.dumps(review, indent=2))
        return

    print("Vault review")
    print(f"Vault: {doctor['vault_name']}")
    print(f"Path: {doctor['vault_dir']}")
    print(f"Version: {doctor['version']}")
    print("CLI ready: yes")
    print(f"Files: {dashboard['files']}")
    print(f"Folders: {dashboard['folders']}")
    print(f"Inbox notes: {dashboard['inbox_notes']}")
    print(f"Draft notes: {dashboard['draft_notes']}")
    print(f"Orphans: {dashboard['orphans']}")
    print(f"Dead ends: {dashboard['deadends']}")
    print(f"Unresolved links: {dashboard['unresolved_links']}")
    print(f"Open tasks: {todo_tasks}")
    print(f"Done tasks: {done_tasks}")
    print("Top tags:")
    if dashboard["top_tags"]:
        for item in dashboard["top_tags"]:
            print(f"  - {item['tag']} ({item['count']})")
    else:
        print("  - none")
    print("Top unresolved links:")
    if top_unresolved:
        for item in top_unresolved:
            print(f"  - {item['link']} ({item['count']})")
    else:
        print("  - none")
    print("Recent files:")
    if recent_files:
        for path in recent_files:
            print(f"  - {path}")
    else:
        print("  - none")
    print("Flags:")
    if flags:
        for flag in flags:
            print(f"  - {flag}")
    else:
        print("  - No obvious cleanup flags.")
    if review["helper_warning_seen"]:
        print("Warning: Obsidian printed macOS helper-app warnings, but review commands still completed successfully.")


def _audit_data(vault_dir: Path, *, tldr_max_line: int) -> dict:
    doctor = _doctor_data(vault_dir)
    unresolved_links = _int_output(_obsidian_command(vault_dir, "unresolved", "total")[0], label="unresolved links")
    orphans = _int_output(_obsidian_command(vault_dir, "orphans", "total")[0], label="orphans")
    deadends = _int_output(_obsidian_command(vault_dir, "deadends", "total")[0], label="dead ends")
    markdownlint_binary = shutil.which("markdownlint") or shutil.which("markdownlint-cli2")

    missing_required_folders = [
        folder
        for folder in REQUIRED_FOLDERS
        if not (vault_dir / folder).is_dir()
    ]

    project_dirs = _project_directories(vault_dir)
    missing_project_overviews = [
        project_dir.as_posix()
        for project_dir in project_dirs
        if not (vault_dir / project_dir / "_Overview.md").is_file()
    ]

    markdown_files = _iter_audit_markdown_files(vault_dir)
    file_read_errors: list[dict[str, str]] = []
    frontmatter_errors: list[dict[str, str]] = []
    missing_tldr: list[str] = []
    late_tldr: list[dict[str, int | str]] = []
    frontmatter_files_checked = 0
    tldr_files_checked = 0

    for relative_path in markdown_files:
        path = vault_dir / relative_path
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            file_read_errors.append({"path": relative_path.as_posix(), "error": str(exc)})
            continue

        lines = text.splitlines()
        frontmatter_block, content_start_index, frontmatter_error = _extract_frontmatter(lines)
        if frontmatter_error:
            frontmatter_errors.append({"path": relative_path.as_posix(), "error": frontmatter_error})
        elif frontmatter_block is not None:
            frontmatter_files_checked += 1
            if yaml is not None:
                try:
                    loaded = yaml.safe_load(frontmatter_block) if frontmatter_block.strip() else {}
                except Exception as exc:  # pragma: no cover - depends on local parser errors
                    frontmatter_errors.append(
                        {
                            "path": relative_path.as_posix(),
                            "error": f"Invalid YAML frontmatter: {exc}",
                        }
                    )
                else:
                    if loaded is not None and not isinstance(loaded, dict):
                        frontmatter_errors.append(
                            {
                                "path": relative_path.as_posix(),
                                "error": "Frontmatter must be a YAML mapping.",
                            }
                        )

        if _should_check_tldr(relative_path):
            tldr_files_checked += 1
            tldr_line = _find_tldr_line(lines, start_index=content_start_index)
            if tldr_line is None:
                missing_tldr.append(relative_path.as_posix())
            elif tldr_line - content_start_index > tldr_max_line:
                late_tldr.append({"path": relative_path.as_posix(), "line": tldr_line})

    audit = {
        "doctor": doctor,
        "obsidian": {
            "unresolved_links": unresolved_links,
            "orphans": orphans,
            "deadends": deadends,
        },
        "tooling": {
            "yaml_available": yaml is not None,
            "markdownlint_available": bool(markdownlint_binary),
            "markdownlint_binary": markdownlint_binary,
        },
        "summary": {
            "required_folders_checked": len(REQUIRED_FOLDERS),
            "project_folders_checked": len(project_dirs),
            "markdown_files_checked": len(markdown_files),
            "tldr_files_checked": tldr_files_checked,
            "frontmatter_files_checked": frontmatter_files_checked,
            "tldr_max_line": tldr_max_line,
        },
        "issues": {
            "missing_required_folders": missing_required_folders,
            "missing_project_overviews": missing_project_overviews,
            "file_read_errors": file_read_errors,
            "frontmatter_errors": frontmatter_errors,
            "missing_tldr": missing_tldr,
            "late_tldr": late_tldr,
        },
    }

    flags: list[str] = []
    if missing_required_folders:
        flags.append(
            f"{len(missing_required_folders)} required {_pluralize(len(missing_required_folders), 'folder')} {_be_verb(len(missing_required_folders))} missing."
        )
    if missing_project_overviews:
        flags.append(
            f"{len(missing_project_overviews)} project {_pluralize(len(missing_project_overviews), 'folder')} {_be_verb(len(missing_project_overviews))} missing _Overview.md."
        )
    if frontmatter_errors:
        flags.append(
            f"{len(frontmatter_errors)} markdown {_pluralize(len(frontmatter_errors), 'file')} {_be_verb(len(frontmatter_errors))} failing frontmatter checks."
        )
    if file_read_errors:
        flags.append(
            f"{len(file_read_errors)} markdown {_pluralize(len(file_read_errors), 'file')} {_be_verb(len(file_read_errors))} unreadable as UTF-8 text."
        )
    if missing_tldr:
        flags.append(
            f"{len(missing_tldr)} {_pluralize(len(missing_tldr), 'note')} {_be_verb(len(missing_tldr))} missing a top-level TL;DR section."
        )
    if late_tldr:
        flags.append(
            f"{len(late_tldr)} {_pluralize(len(late_tldr), 'note')} {_be_verb(len(late_tldr))} placing TL;DR too far from the top."
        )
    if unresolved_links > 0:
        flags.append(
            f"{unresolved_links} unresolved {_pluralize(unresolved_links, 'link')} {_be_verb(unresolved_links)} still present."
        )
    audit["flags"] = flags
    audit["ok"] = not flags
    return audit


def _audit(vault_dir: Path, *, json_output: bool, limit: int, tldr_max_line: int) -> None:
    audit = _audit_data(vault_dir, tldr_max_line=tldr_max_line)
    if json_output:
        print(json.dumps(audit, indent=2))
        return

    doctor = audit["doctor"]
    obsidian = audit["obsidian"]
    summary = audit["summary"]
    issues = audit["issues"]

    print("Vault audit")
    print(f"Vault: {doctor['vault_name']}")
    print(f"Path: {doctor['vault_dir']}")
    print(f"Version: {doctor['version']}")
    print("CLI ready: yes")
    print(f"Markdown files checked: {summary['markdown_files_checked']}")
    print(f"Project folders checked: {summary['project_folders_checked']}")
    print(f"TL;DR checks: {summary['tldr_files_checked']}")
    print(f"Frontmatter checks: {summary['frontmatter_files_checked']}")
    print(f"Unresolved links: {obsidian['unresolved_links']}")
    print(f"Orphans: {obsidian['orphans']}")
    print(f"Dead ends: {obsidian['deadends']}")
    print(f"PyYAML available: {'yes' if audit['tooling']['yaml_available'] else 'no'}")
    print(f"markdownlint available: {'yes' if audit['tooling']['markdownlint_available'] else 'no'}")
    _print_samples("Missing required folders", issues["missing_required_folders"], limit=limit)
    _print_samples("Missing project overviews", issues["missing_project_overviews"], limit=limit)
    _print_samples("Unreadable markdown files", issues["file_read_errors"], limit=limit)
    _print_samples("Frontmatter errors", issues["frontmatter_errors"], limit=limit)
    _print_samples("Missing TL;DR", issues["missing_tldr"], limit=limit)
    _print_samples("Late TL;DR", issues["late_tldr"], limit=limit)
    print("Flags:")
    if audit["flags"]:
        for flag in audit["flags"]:
            print(f"  - {flag}")
    else:
        print("  - No audit issues detected.")
    if doctor["helper_warning_seen"]:
        print("Warning: Obsidian printed macOS helper-app warnings, but audit commands still completed successfully.")


def _fix_tldr(vault_dir: Path, *, dry_run: bool, limit: int) -> None:
    missing_tldr = _missing_tldr_paths(vault_dir)
    if dry_run:
        print(f"Notes missing TL;DR: {len(missing_tldr)}")
        if missing_tldr:
            for path in missing_tldr[:limit]:
                print(f"  - {path}")
            remaining = len(missing_tldr) - limit
            if remaining > 0:
                print(f"  - ... {remaining} more")
        else:
            print("  - none")
        return

    updated: list[str] = []
    for relative_path_str in missing_tldr:
        relative_path = Path(relative_path_str)
        path = vault_dir / relative_path
        text = path.read_text(encoding="utf-8")
        updated_text = _insert_tldr(text)
        if updated_text != text:
            path.write_text(updated_text, encoding="utf-8")
            updated.append(relative_path_str)

    print(f"Updated notes: {len(updated)}")
    if updated:
        for path in updated[:limit]:
            print(f"  - {path}")
        remaining = len(updated) - limit
        if remaining > 0:
            print(f"  - ... {remaining} more")


def _structure_report(
    vault_dir: Path,
    *,
    json_output: bool,
    dry_run: bool,
    limit: int,
    hotspot_limit: int,
    output_path: str,
) -> None:
    output_relative = _normalize_relative_path(output_path, label="Output path")
    data = _structure_report_data(
        vault_dir,
        output_relative=output_relative,
        limit=limit,
        hotspot_limit=hotspot_limit,
    )
    if json_output:
        print(json.dumps(data, indent=2))
        return

    report_text = _structure_report_markdown(data)
    output_abs = vault_dir / output_relative
    if not dry_run:
        output_abs.parent.mkdir(parents=True, exist_ok=True)
        output_abs.write_text(report_text, encoding="utf-8")

    counts = data["counts"]
    print(f"Notes analyzed: {data['scope']['notes_analyzed']}")
    print(f"Isolated notes: {counts['isolated']}")
    print(f"Orphans: {counts['orphans']}")
    print(f"Dead ends: {counts['deadends']}")
    if dry_run:
        print(f"Would write report: {output_relative.as_posix()}")
    else:
        print(f"Wrote report: {output_relative.as_posix()}")


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
    _, relative_folder = _resolve_vault_path(
        vault_dir,
        folder,
        label="Target folder",
        must_exist=True,
        expect_directory=True,
    )
    file_name = _normalize_note_name(name) if name else _slugify(title)
    content = _compose_note(title, intro=body)
    cmd = ["create", f"name={file_name}", f"path={relative_folder}", f"content={_encode_cli_text(content)}"]
    if overwrite:
        cmd.append("overwrite")
    relative_path = f"{relative_folder}/{file_name}.md"
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
    source_abs, source_relative = _resolve_vault_path(
        vault_dir,
        source,
        label="Source note",
        must_exist=True,
        expect_directory=False,
    )
    source_path = Path(source_relative)
    extension = source_path.suffix or ".md"
    if keep_name:
        base_name = _normalize_note_name(source_path.name)
    elif name:
        base_name = _slugify(_normalize_note_name(name))
    else:
        base_name = _slugify(source_path.stem)
    relative_folder = project_dir.relative_to(vault_dir)
    if subdir:
        relative_folder = relative_folder / _normalize_relative_path(subdir, label="Subdirectory")
    destination = (relative_folder / f"{base_name}{extension}").as_posix()
    if dry_run:
        print(f"Would move: {source_relative} -> {destination}")
        return
    _obsidian_command(vault_dir, "move", f"path={source_relative}", f"to={destination}")
    print(f"Moved: {source_relative} -> {destination}")
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

    review_parser = subparsers.add_parser("review", help="Run a one-click vault review using Obsidian CLI data")
    review_parser.add_argument("--json", action="store_true", help="Output JSON")
    review_parser.add_argument("--tags-limit", type=int, default=10, help="Number of top tags to show")
    review_parser.add_argument(
        "--unresolved-limit",
        type=int,
        default=10,
        help="Number of unresolved links to include",
    )
    review_parser.add_argument(
        "--recent-limit",
        type=int,
        default=10,
        help="Number of recent files to include",
    )

    audit_parser = subparsers.add_parser(
        "audit",
        help="Run policy checks for vault folders, project overviews, TL;DR sections, and frontmatter",
    )
    audit_parser.add_argument("--json", action="store_true", help="Output JSON")
    audit_parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Number of issue samples to print per section",
    )
    audit_parser.add_argument(
        "--tldr-max-line",
        type=int,
        default=40,
        help="Maximum number of lines after frontmatter for the TL;DR heading to count as near the top",
    )

    fix_tldr_parser = subparsers.add_parser(
        "fix-tldr",
        help="Insert a placeholder TL;DR section into notes that are missing one",
    )
    fix_tldr_parser.add_argument("--dry-run", action="store_true", help="List target notes without editing them")
    fix_tldr_parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Number of sample paths to print",
    )

    structure_report_parser = subparsers.add_parser(
        "structure-report",
        help="Build a local note-graph cleanup report for orphan and dead-end notes",
    )
    structure_report_parser.add_argument("--json", action="store_true", help="Output JSON instead of markdown")
    structure_report_parser.add_argument("--dry-run", action="store_true", help="Print the summary without writing the note")
    structure_report_parser.add_argument(
        "--limit",
        type=int,
        default=25,
        help="Number of sample notes to include per report section",
    )
    structure_report_parser.add_argument(
        "--hotspot-limit",
        type=int,
        default=10,
        help="Number of hotspot folders to include",
    )
    structure_report_parser.add_argument(
        "--output-path",
        default=STRUCTURE_REPORT_DEFAULT,
        help=f"Vault-relative markdown report path. Default: {STRUCTURE_REPORT_DEFAULT}",
    )

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

    if args.command == "review":
        _review(
            vault_dir,
            json_output=args.json,
            tags_limit=args.tags_limit,
            unresolved_limit=args.unresolved_limit,
            recent_limit=args.recent_limit,
        )
        return

    if args.command == "audit":
        _audit(
            vault_dir,
            json_output=args.json,
            limit=args.limit,
            tldr_max_line=args.tldr_max_line,
        )
        return

    if args.command == "fix-tldr":
        _fix_tldr(
            vault_dir,
            dry_run=args.dry_run,
            limit=args.limit,
        )
        return

    if args.command == "structure-report":
        _structure_report(
            vault_dir,
            json_output=args.json,
            dry_run=args.dry_run,
            limit=args.limit,
            hotspot_limit=args.hotspot_limit,
            output_path=args.output_path,
        )
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
