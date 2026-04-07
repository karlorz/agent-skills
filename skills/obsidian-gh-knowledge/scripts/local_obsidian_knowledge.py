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
RAW_SUBMODULE_DIR = "raw"
RAW_INBOX_NAME = "inbox"
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
    RAW_SUBMODULE_DIR,
    "assets",
    "4️⃣-Attachments",
    "archive",
    "_archive",
    "node_modules",
}
AUDIT_SKIP_FILE_NAMES = {
    "conflict-files-obsidian-git.md",
}
TLDR_SKIP_TOP_LEVEL_DIRS = {
    "agent-skills",
    "help_obsidian_md",
    RAW_SUBMODULE_DIR,
}
TLDR_SKIP_FILE_NAMES = {
    "README.md",
    "AGENTS.md",
    "CLAUDE.md",
    "_Overview.md",
}
STRUCTURE_REPORT_DEFAULT = "1️⃣-Index/vault-structure-cleanup-report.md"
SIMPLIFY_REVIEW_DEFAULT = "1️⃣-Index/vault-simplify-dedupe-review.md"
STRUCTURE_ROOT_HUB = Path("1️⃣-Index/vault-operations-index.md")
SNAPSHOT_REPORT_CONTRACT = Path("1️⃣-Index/vault-snapshot-report-contract.md")
VAULT_EXCEPTION_DASHBOARD = Path("1️⃣-Index/vault-exception-dashboard.md")
WEEKLY_REVIEW_RUNBOOK = Path("1️⃣-Index/weekly-vault-review-runbook.md")
STRUCTURE_PROMPT_HUB = Path("1️⃣-Index/prompt-library.md")
STRUCTURE_CMUX_HUB = Path("1️⃣-Index/cmux-local-workflows-index.md")
OVERVIEW_MAX_LINES = 200
PROJECT_DIR_SKIP_NAMES = {
    "archive",
    "_archive",
}
ARCHIVE_INDEX_NAME = "_Archive-Index.md"
TLDR_PATTERN = re.compile(r"^\s*##\s+TL;DR\s*$", re.IGNORECASE)
WIKILINK_PATTERN = re.compile(r"!?\[\[([^\]]+)\]\]")
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
INTENTIONAL_DUPLICATE_STEMS = {
    "_overview",
    "_archive-index",
    "readme",
    "agents",
    "claude",
}


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


def _raw_submodule_relative_path(config: dict) -> Path:
    value = config.get("raw_submodule_path")
    if isinstance(value, str) and value.strip():
        return Path(_normalize_relative_path(value, label="Raw submodule path"))
    return Path(RAW_SUBMODULE_DIR)


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


def _git_stdout(vault_dir: Path, *args: str, check: bool = True) -> str:
    result = _run_process(["git", *args], cwd=vault_dir)
    if check and result.returncode != 0:
        details = "\n".join(part for part in [(result.stdout or "").strip(), (result.stderr or "").strip()] if part)
        message = f"Git command failed ({result.returncode}): git {' '.join(args)}"
        if details:
            message = f"{message}\n{details}"
        _die(message, exit_code=result.returncode)
    return (result.stdout or "").strip()


def _submodule_status(vault_dir: Path, relative_path: Path) -> dict:
    info = {
        "path": relative_path.as_posix(),
        "configured": False,
        "exists": False,
        "initialized": False,
        "url": None,
        "head": None,
        "dirty": False,
    }
    gitmodules = vault_dir / ".gitmodules"
    if gitmodules.exists():
        url = _git_stdout(
            vault_dir,
            "config",
            "--file",
            ".gitmodules",
            "--get",
            f"submodule.{relative_path.as_posix()}.url",
            check=False,
        )
        if url:
            info["configured"] = True
            info["url"] = url

    submodule_dir = vault_dir / relative_path
    info["exists"] = submodule_dir.exists()
    if not submodule_dir.exists():
        return info

    git_ref = submodule_dir / ".git"
    info["initialized"] = git_ref.exists()
    if not info["initialized"]:
        return info

    head = _git_stdout(vault_dir, "submodule", "status", "--", relative_path.as_posix(), check=False)
    if head:
        cleaned = head.strip()
        if cleaned and cleaned[0] in {"-", "+", "U"}:
            cleaned = cleaned[1:].strip()
        if cleaned:
            info["head"] = cleaned.split()[0]

    sub_status = _run_process(["git", "status", "--porcelain=v1"], cwd=submodule_dir)
    info["dirty"] = bool((sub_status.stdout or "").strip())
    return info


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
    stripped = output.strip()
    if re.fullmatch(r"No .+ found\.", stripped):
        return [], helper_warning
    try:
        data = json.loads(output or "[]")
    except json.JSONDecodeError as exc:
        _die(f"Failed to parse JSON output for {label}.\n{exc}\n{output}")
    return data, helper_warning


def _should_skip_audit_path(relative_path: Path) -> bool:
    if relative_path.name in AUDIT_SKIP_FILE_NAMES:
        return True
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


def _is_regular_markdown_file(path: Path) -> bool:
    return path.is_file() and not path.is_symlink() and path.suffix.lower() == ".md"


def _iter_audit_markdown_files(vault_dir: Path) -> list[Path]:
    markdown_files: list[Path] = []
    for path in vault_dir.rglob("*.md"):
        if not _is_regular_markdown_file(path):
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
        if "path" in item and "lines" in item:
            return f"{item['path']}: {item['lines']} lines"
        if "path" in item and "count" in item:
            return f"{item['path']}: {item['count']} pending items"
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


def _markdown_note_link(source_relative: Path, target_relative: Path, *, display: str | None = None) -> str:
    source_parent = source_relative.parent.as_posix()
    start = source_parent if source_parent not in {"", "."} else "."
    target = os.path.relpath(target_relative.as_posix(), start=start).replace("\\", "/")
    label = display or target_relative.stem
    return f"[{label}]({target})"


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


def _folder_active_markdown_paths(vault_dir: Path, folder_relative: str) -> list[Path]:
    folder_path = vault_dir / folder_relative
    if not folder_path.is_dir():
        return []

    paths: list[Path] = []
    for path in folder_path.rglob("*.md"):
        if not _is_regular_markdown_file(path):
            continue
        relative_path = path.relative_to(vault_dir)
        nested_parts = relative_path.parts[1:-1]
        if any(part.startswith(".") or part in {"archive", "_archive"} for part in nested_parts):
            continue
        paths.append(relative_path)
    return sorted(paths)


def _intake_lane_snapshot(vault_dir: Path, *, raw_root_relative: str = RAW_SUBMODULE_DIR) -> dict:
    raw_root = _normalize_relative_path(raw_root_relative, label="Raw root path").as_posix()
    raw_inbox_relative = f"{raw_root}/{RAW_INBOX_NAME}"
    raw_inbox_paths = _folder_active_markdown_paths(vault_dir, raw_inbox_relative)
    curated_inbox_paths = _folder_active_markdown_paths(vault_dir, INBOX_DIR)
    draft_paths = _folder_active_markdown_paths(vault_dir, DRAFTS_DIR)
    return {
        "raw_root_path": raw_root,
        "raw_inbox_path": raw_inbox_relative,
        "raw_inbox_items": len(raw_inbox_paths),
        "raw_inbox_paths": [path.as_posix() for path in raw_inbox_paths],
        "curated_inbox_notes": len(curated_inbox_paths),
        "curated_inbox_paths": [path.as_posix() for path in curated_inbox_paths],
        "draft_notes": len(draft_paths),
        "draft_paths": [path.as_posix() for path in draft_paths],
    }


def _normalize_dedupe_key(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip()).lower()


def _frontmatter_aliases(frontmatter: object) -> list[str]:
    if not isinstance(frontmatter, dict):
        return []

    raw_aliases: list[str] = []
    for key in ("aliases", "alias"):
        value = frontmatter.get(key)
        if isinstance(value, str):
            raw_aliases.append(value)
        elif isinstance(value, list):
            raw_aliases.extend(item for item in value if isinstance(item, str))

    aliases: list[str] = []
    seen: set[str] = set()
    for alias in raw_aliases:
        normalized = re.sub(r"\s+", " ", alias.strip())
        if not normalized:
            continue
        dedupe_key = normalized.lower()
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        aliases.append(normalized)
    return aliases


def _duplicate_basename_groups(note_paths_list: list[Path]) -> list[dict[str, object]]:
    basename_groups: dict[str, list[Path]] = defaultdict(list)
    basename_labels: dict[str, str] = {}

    for path in note_paths_list:
        dedupe_key = _normalize_dedupe_key(path.stem)
        if dedupe_key in INTENTIONAL_DUPLICATE_STEMS:
            continue
        basename_groups[dedupe_key].append(path)
        basename_labels.setdefault(dedupe_key, path.stem)

    duplicate_groups: list[dict[str, object]] = []
    for dedupe_key, paths in basename_groups.items():
        unique_paths = sorted(
            {path.as_posix(): path for path in paths}.values(),
            key=lambda path: path.as_posix(),
        )
        if len(unique_paths) < 2:
            continue
        duplicate_groups.append(
            {
                "value": basename_labels[dedupe_key],
                "count": len(unique_paths),
                "paths": [path.as_posix() for path in unique_paths],
                "links": [_structure_note_link(path) for path in unique_paths],
                "folders": sorted({path.parent.as_posix() for path in unique_paths}),
            }
        )

    return sorted(
        duplicate_groups,
        key=lambda item: (-item["count"], str(item["value"]).lower(), item["paths"][0]),
    )


def _duplicate_alias_groups(vault_dir: Path, note_paths_list: list[Path]) -> list[dict[str, object]]:
    if yaml is None:
        return []

    alias_groups: dict[str, dict[str, Path]] = defaultdict(dict)
    alias_labels: dict[str, str] = {}

    for relative_path in note_paths_list:
        path = vault_dir / relative_path
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        frontmatter_block, _, frontmatter_error = _extract_frontmatter(text.splitlines())
        if frontmatter_error or frontmatter_block is None:
            continue

        try:
            loaded = yaml.safe_load(frontmatter_block) if frontmatter_block.strip() else {}
        except Exception:
            continue

        for alias in _frontmatter_aliases(loaded):
            dedupe_key = _normalize_dedupe_key(alias)
            alias_labels.setdefault(dedupe_key, alias)
            alias_groups[dedupe_key][relative_path.as_posix()] = relative_path

    duplicate_groups: list[dict[str, object]] = []
    for dedupe_key, paths_map in alias_groups.items():
        unique_paths = sorted(paths_map.values(), key=lambda path: path.as_posix())
        if len(unique_paths) < 2:
            continue
        duplicate_groups.append(
            {
                "value": alias_labels[dedupe_key],
                "count": len(unique_paths),
                "paths": [path.as_posix() for path in unique_paths],
                "links": [_structure_note_link(path) for path in unique_paths],
                "folders": sorted({path.parent.as_posix() for path in unique_paths}),
            }
        )

    return sorted(
        duplicate_groups,
        key=lambda item: (-item["count"], str(item["value"]).lower(), item["paths"][0]),
    )


def _structure_analysis(vault_dir: Path, *, exclude_relative: Path | None = None) -> dict:
    note_paths_list = [
        relative_path
        for relative_path in _iter_audit_markdown_files(vault_dir)
        if relative_path != exclude_relative
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
    overview_map = {
        path: _structure_overview_path(path, note_paths)
        for path in note_paths_list
    }

    return {
        "note_paths_list": note_paths_list,
        "note_paths": note_paths,
        "outgoing_map": outgoing_map,
        "inbound_map": inbound_map,
        "orphans": orphans,
        "deadends": deadends,
        "isolated": isolated,
        "overview_map": overview_map,
        "read_errors": read_errors,
    }


def _structure_report_data(
    vault_dir: Path,
    *,
    output_relative: Path,
    limit: int,
    hotspot_limit: int,
    analysis: dict | None = None,
) -> dict:
    analysis = analysis or _structure_analysis(vault_dir, exclude_relative=output_relative)
    note_paths_list = analysis["note_paths_list"]
    note_paths = analysis["note_paths"]
    orphans = analysis["orphans"]
    deadends = analysis["deadends"]
    isolated = analysis["isolated"]
    overview_map = analysis["overview_map"]
    read_errors = analysis["read_errors"]

    def _sample_rows(paths: list[Path]) -> list[dict[str, str]]:
        rows: list[dict[str, str]] = []
        for path in paths[:limit]:
            overview = overview_map.get(path)
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
        f"- Treat this as a snapshot report under {_structure_note_link(SNAPSHOT_REPORT_CONTRACT, display='Vault Snapshot Report Contract')}. Use {_structure_note_link(VAULT_EXCEPTION_DASHBOARD, display='Vault Exception Dashboard')} or {_structure_note_link(WEEKLY_REVIEW_RUNBOOK, display='Weekly Vault Review Runbook')} for the live review sequence.",
        "",
        "## Scope",
        f"- Generated on **{data['generated_at']}**.",
        f"- Active-scope scan of **{scope['notes_analyzed']}** markdown notes.",
        "- Excludes `archive`, `_archive`, attachments/assets, hidden/system folders, and the generated cleanup report itself.",
        "- Uses local Markdown link parsing for wikilinks and internal markdown paths, not the unstable live Obsidian orphan/dead-end list commands.",
        "",
        "## Snapshot Summary",
        "",
        f"- Fully isolated notes in active scope: **{counts['isolated']}**",
        f"- Notes with no inbound links in active scope: **{counts['orphans']}**",
        f"- Notes with no outbound links in active scope: **{counts['deadends']}**",
        "",
        "## Hotspots",
    ]
    if not (orphan_hotspots or deadend_hotspots or isolated_sample or orphan_sample or deadend_sample):
        lines.extend([
            "",
            "- No current orphan, dead-end, or isolated hotspots were found in the active scope.",
        ])
    else:
        if orphan_hotspots:
            lines.extend([
                "",
                "### Orphan Hotspots",
                "| Folder | Count |",
                "| --- | ---: |",
            ])
            for item in orphan_hotspots:
                lines.append(f"| `{item['folder']}` | {item['count']} |")

        if deadend_hotspots:
            lines.extend([
                "",
                "### Dead-End Hotspots",
                "| Folder | Count |",
                "| --- | ---: |",
            ])
            for item in deadend_hotspots:
                lines.append(f"| `{item['folder']}` | {item['count']} |")

        def _append_rows(title: str, rows: list[dict[str, str]]) -> None:
            if not rows:
                return
            lines.extend([
                "",
                f"### {title}",
                "| Note | Folder | Suggested Overview |",
                "| --- | --- | --- |",
            ])
            for row in rows:
                lines.append(f"| {row['note_link']} | `{row['folder']}` | {row['overview_link']} |")

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
        "## Related",
        f"- {_structure_note_link(STRUCTURE_ROOT_HUB, display='Vault Operations Index')}",
        f"- {_structure_note_link(SNAPSHOT_REPORT_CONTRACT, display='Vault Snapshot Report Contract')}",
        f"- {_structure_note_link(VAULT_EXCEPTION_DASHBOARD, display='Vault Exception Dashboard')}",
        f"- {_structure_note_link(WEEKLY_REVIEW_RUNBOOK, display='Weekly Vault Review Runbook')}",
        "",
    ])

    return "\n".join(lines)


def _find_section_bounds(lines: list[str], heading: str) -> tuple[int, int] | None:
    heading_pattern = re.compile(rf"^\s*##\s+{re.escape(heading)}\s*$", re.IGNORECASE)
    start = None
    for index, line in enumerate(lines):
        if heading_pattern.match(line):
            start = index
            break
    if start is None:
        return None
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if re.match(r"^\s*##\s+", lines[index]):
            end = index
            break
    return start, end


def _structure_cleanup_inbox_count(lines: list[str]) -> int:
    bounds = _find_section_bounds(lines, "Structure Cleanup Inbox")
    if bounds is None:
        return 0
    start, end = bounds
    count = 0
    for line in lines[start + 1:end]:
        stripped = line.strip()
        if stripped.startswith("- [[") or stripped.startswith("- ["):
            count += 1
    return count


def _text_has_wikilink_target(text: str, target_relative: Path) -> bool:
    target_no_ext = target_relative.with_suffix("").as_posix()
    target_stem = target_relative.stem
    for match in WIKILINK_PATTERN.finditer(text):
        raw = match.group(1).split("|", 1)[0].split("#", 1)[0].strip()
        if raw in {target_no_ext, target_relative.as_posix(), target_stem}:
            return True
        if raw.endswith(f"/{target_stem}") or raw.endswith(f"/{target_stem}.md"):
            return True
    return False


def _ensure_related_link(text: str, target_relative: Path, *, display: str) -> tuple[str, bool]:
    if _text_has_wikilink_target(text, target_relative):
        return text, False

    link_line = f"- {_structure_note_link(target_relative, display=display)}"
    lines = text.splitlines()
    bounds = _find_section_bounds(lines, "Related")
    if bounds is not None:
        start, end = bounds
        body = lines[start + 1:end]
        while body and not body[-1].strip():
            body.pop()
        if body and body[-1].strip():
            body.append("")
        body.append(link_line)
        lines = lines[:start + 1] + [""] + body + [""] + lines[end:]
        return "\n".join(lines).rstrip() + "\n", True

    while lines and not lines[-1].strip():
        lines.pop()
    lines.extend(["", "## Related", "", link_line, ""])
    return "\n".join(lines).rstrip() + "\n", True


def _ensure_related_overview_link(text: str, overview_relative: Path) -> tuple[str, bool]:
    return _ensure_related_link(text, overview_relative, display="Overview")


def _structure_cleanup_anchor_index(lines: list[str]) -> int:
    anchor_patterns = [
        re.compile(r"^\s*##\s+Archive", re.IGNORECASE),
        re.compile(r"^\s*##\s+Dev Log Archive", re.IGNORECASE),
        re.compile(r"^\s*##\s+Cross-References", re.IGNORECASE),
        re.compile(r"^\s*##\s+External Links", re.IGNORECASE),
        re.compile(r"^\s*##\s+Document Status Legend", re.IGNORECASE),
        re.compile(r"^\s*\*\*Last Updated\*\*", re.IGNORECASE),
    ]
    for index, line in enumerate(lines):
        if any(pattern.match(line) for pattern in anchor_patterns):
            return index
    return len(lines)


def _ensure_overview_cleanup_links(text: str, note_relatives: list[Path]) -> tuple[str, bool]:
    desired_lines = [f"- {_structure_note_link(path)}" for path in sorted(note_relatives, key=lambda p: p.as_posix())]
    if not desired_lines:
        return text, False

    lines = text.splitlines()
    bounds = _find_section_bounds(lines, "Structure Cleanup Inbox")
    changed = False

    if bounds is not None:
        start, end = bounds
        section_body = lines[start + 1:end]
        insert_body = list(section_body)
        existing_text = "\n".join(section_body)
        for link_line in desired_lines:
            if link_line not in existing_text:
                if insert_body and insert_body[-1].strip():
                    insert_body.append("")
                insert_body.append(link_line)
                changed = True
        if not changed:
            return text, False
        lines = lines[:start + 1] + insert_body + lines[end:]
        return "\n".join(lines).rstrip() + "\n", True

    insert_at = _structure_cleanup_anchor_index(lines)
    section = [
        "## Structure Cleanup Inbox",
        "",
        "Auto-generated candidates that still need manual placement in this MOC.",
        "",
        *desired_lines,
        "",
    ]
    if insert_at > 0 and lines[insert_at - 1].strip():
        section.insert(0, "")
    lines = lines[:insert_at] + section + lines[insert_at:]
    return "\n".join(lines).rstrip() + "\n", True


def _fallback_hub_for_path(relative_path: Path) -> Path | None:
    if relative_path in {
        STRUCTURE_ROOT_HUB,
        STRUCTURE_PROMPT_HUB,
        STRUCTURE_CMUX_HUB,
        Path(STRUCTURE_REPORT_DEFAULT),
    }:
        return None
    if relative_path.parts and relative_path.parts[0] == "prompts":
        return STRUCTURE_PROMPT_HUB
    if relative_path.parts and relative_path.parts[0] == "cmux":
        return STRUCTURE_CMUX_HUB
    if relative_path.parts and relative_path.parts[0] in {"100-Templates", "3️⃣-Plugins", "agent-skills", "1️⃣-Index"}:
        return STRUCTURE_ROOT_HUB
    if len(relative_path.parts) == 1:
        return STRUCTURE_ROOT_HUB
    return None


def _skip_hub_backlink(relative_path: Path) -> bool:
    if relative_path in {
        Path("CLAUDE.md"),
        Path("1️⃣-Index/CLAUDE.md"),
    }:
        return True
    return False


def _hub_title(relative_path: Path) -> str:
    if relative_path == STRUCTURE_ROOT_HUB:
        return "Vault Operations Index"
    if relative_path == STRUCTURE_PROMPT_HUB:
        return "Prompt Library"
    if relative_path == STRUCTURE_CMUX_HUB:
        return "cmux Local Workflows Index"
    return relative_path.stem


def _hub_summary(relative_path: Path) -> list[str]:
    if relative_path == STRUCTURE_ROOT_HUB:
        return [
            "- Central index for root docs, local operational notes, plugins, templates, and skill references that do not belong in project MOCs.",
            "- Generated by `structure-fix` so non-project notes have a stable navigation anchor.",
        ]
    if relative_path == STRUCTURE_PROMPT_HUB:
        return [
            "- Central index for reusable research and bootstrap prompts stored in `prompts/`.",
            "- Use this note as the navigation anchor for prompt notes that are intentionally outside project folders.",
        ]
    if relative_path == STRUCTURE_CMUX_HUB:
        return [
            "- Central index for local `cmux/` workflow notes that are not stored under the main project MOC tree.",
            "- Use this note to keep scratchpad and workflow-specific cmux notes linked into the vault graph.",
        ]
    return ["- Auto-generated structure hub."]


def _hub_group_label(relative_path: Path) -> str:
    if len(relative_path.parts) == 1:
        return "Root Notes"
    top = relative_path.parts[0]
    mapping = {
        "1️⃣-Index": "Index Notes",
        "3️⃣-Plugins": "Plugin Notes",
        "100-Templates": "Templates",
        "agent-skills": "Local Skill Docs",
        "prompts": "Prompt Notes",
        "cmux": "cmux Local Notes",
    }
    return mapping.get(top, top)


def _hub_note_markdown(relative_path: Path, note_paths: list[Path]) -> str:
    title = _hub_title(relative_path)
    grouped: dict[str, list[Path]] = defaultdict(list)
    for note_path in sorted(note_paths, key=lambda p: p.as_posix()):
        grouped[_hub_group_label(note_path)].append(note_path)

    lines = [
        f"# {title}",
        "",
        "## TL;DR",
        *_hub_summary(relative_path),
        "",
    ]
    for heading, paths in sorted(grouped.items()):
        lines.extend([f"## {heading}", ""])
        for path in paths:
            if relative_path.parent != Path(".") and path.parent == Path("."):
                lines.append(f"- {_markdown_note_link(relative_path, path)}")
            else:
                lines.append(f"- {_structure_note_link(path)}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def _iter_archive_markdown_files(vault_dir: Path) -> list[Path]:
    markdown_files: list[Path] = []
    for path in vault_dir.rglob("*.md"):
        if not _is_regular_markdown_file(path):
            continue
        relative_path = path.relative_to(vault_dir)
        if relative_path.name == ARCHIVE_INDEX_NAME:
            continue
        if any(part in {"archive", "_archive"} for part in relative_path.parts[:-1]):
            markdown_files.append(relative_path)
    return sorted(markdown_files)


def _archive_index_for_note(vault_dir: Path, relative_path: Path) -> Path | None:
    direct_candidate = relative_path.parent / ARCHIVE_INDEX_NAME
    if (vault_dir / direct_candidate).is_file():
        return direct_candidate
    for parent in relative_path.parents:
        if str(parent) in {"", "."}:
            break
        if parent.name in {"archive", "_archive"}:
            return parent / ARCHIVE_INDEX_NAME
    return None


def _archive_index_title(relative_path: Path) -> str:
    parent = relative_path.parent
    if parent == Path("0️⃣-Inbox/_archive"):
        return "Inbox Archive"
    if parent == Path("2️⃣-Drafts/_archive"):
        return "Draft Archive"
    if parent.name in {"archive", "_archive"} and len(parent.parts) >= 2:
        return f"{parent.parent.name} Archive"
    return f"{parent.name} Archive"


def _archive_parent_link(vault_dir: Path, relative_path: Path) -> str | None:
    parent = relative_path.parent
    if parent == Path("0️⃣-Inbox/_archive") or parent == Path("2️⃣-Drafts/_archive"):
        return _structure_note_link(STRUCTURE_ROOT_HUB, display="Vault Operations Index")
    for ancestor in parent.parents:
        if str(ancestor) in {"", "."}:
            break
        overview = ancestor / "_Overview.md"
        if (vault_dir / overview).is_file():
            return _structure_note_link(overview, display="Overview")
    return None


def _archive_index_markdown(vault_dir: Path, relative_path: Path, note_paths: list[Path]) -> str:
    title = _archive_index_title(relative_path)
    parent_link = _archive_parent_link(vault_dir, relative_path)
    lines = [
        f"# {title}",
        "",
        "## TL;DR",
        f"- Archive index for notes stored under `{relative_path.parent.as_posix()}`.",
        "- Generated by `archive-fix` so archived notes keep a minimal navigation anchor without re-entering the active note graph.",
        "",
    ]
    if parent_link:
        lines.extend([
            "## Parent Context",
            "",
            f"- {parent_link}",
            "",
        ])
    lines.extend([
        "## Archived Notes",
        "",
    ])
    for note_path in sorted(note_paths, key=lambda p: p.as_posix()):
        lines.append(f"- {_structure_note_link(note_path)}")
    lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def _doctor_data(vault_dir: Path) -> dict:
    config = _load_config()
    help_output, help_stderr, helper_warning = _obsidian_command(vault_dir, "help")
    version_output, _, version_helper = _obsidian_command(vault_dir, "version")
    vault_name, _, name_helper = _obsidian_command(vault_dir, "vault", "info=name")
    vault_path, _, path_helper = _obsidian_command(vault_dir, "vault", "info=path")
    helper_warning = helper_warning or version_helper or name_helper or path_helper
    raw_submodule = _submodule_status(vault_dir, _raw_submodule_relative_path(config))
    return {
        "vault_dir": str(vault_dir),
        "vault_name": vault_name.strip() or config.get("vault_name") or vault_dir.name,
        "vault_path_reported_by_cli": vault_path.strip(),
        "config_path": str(CONFIG_PATH),
        "default_repo": config.get("default_repo"),
        "prefer_local": config.get("prefer_local"),
        "raw_submodule": raw_submodule,
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
    raw = data["raw_submodule"]
    raw_state = "missing"
    if raw["configured"] and raw["initialized"]:
        raw_state = "ready"
    elif raw["configured"] and raw["exists"]:
        raw_state = "present but not initialized"
    elif raw["configured"]:
        raw_state = "configured but absent"
    print(f"Raw submodule: {raw['path']} ({raw_state})")
    if raw["url"]:
        print(f"Raw repo: {raw['url']}")
    if raw["head"]:
        print(f"Raw HEAD: {raw['head']}")
    if raw["dirty"]:
        print("Warning: raw submodule has uncommitted changes.")
    print("CLI ready: yes")
    if helper_warning:
        print("Warning: Obsidian printed macOS helper-app warnings, but CLI commands still completed successfully.")
    if help_stderr:
        print("CLI stderr:")
        for line in help_stderr:
            print(f"  {line}")


def _dashboard_data(vault_dir: Path, *, tags_limit: int) -> dict:
    config = _load_config()
    intake = _intake_lane_snapshot(vault_dir, raw_root_relative=_raw_submodule_relative_path(config).as_posix())
    active_scope = _structure_analysis(vault_dir, exclude_relative=Path(STRUCTURE_REPORT_DEFAULT))
    stats = {
        "vault": (vault_dir.name),
        "path": str(vault_dir),
        "files": _int_output(_obsidian_command(vault_dir, "files", "total")[0], label="files"),
        "folders": _int_output(_obsidian_command(vault_dir, "folders", "total")[0], label="folders"),
        "raw_root_path": intake["raw_root_path"],
        "raw_inbox_path": intake["raw_inbox_path"],
        "raw_inbox_items": intake["raw_inbox_items"],
        "raw_inbox_paths": intake["raw_inbox_paths"],
        "curated_inbox_notes": intake["curated_inbox_notes"],
        "curated_inbox_paths": intake["curated_inbox_paths"],
        "inbox_notes": intake["curated_inbox_notes"],
        "inbox_paths": intake["curated_inbox_paths"],
        "draft_notes": intake["draft_notes"],
        "draft_paths": intake["draft_paths"],
        "orphans": _int_output(_obsidian_command(vault_dir, "orphans", "total")[0], label="orphans"),
        "deadends": _int_output(_obsidian_command(vault_dir, "deadends", "total")[0], label="deadends"),
        "unresolved_links": _int_output(
            _obsidian_command(vault_dir, "unresolved", "total")[0], label="unresolved links"
        ),
        "active_scope_notes": len(active_scope["note_paths_list"]),
        "active_scope_orphans": len(active_scope["orphans"]),
        "active_scope_deadends": len(active_scope["deadends"]),
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
    print(f"Raw intake items: {stats['raw_inbox_items']}")
    print(f"Curated inbox notes: {stats['curated_inbox_notes']}")
    print(f"Draft notes: {stats['draft_notes']}")
    print(f"Full-vault orphans: {stats['orphans']}")
    print(f"Full-vault dead ends: {stats['deadends']}")
    print(f"Active-scope notes: {stats['active_scope_notes']}")
    print(f"Active-scope orphans: {stats['active_scope_orphans']}")
    print(f"Active-scope dead ends: {stats['active_scope_deadends']}")
    print(f"Unresolved links: {stats['unresolved_links']}")
    print("Top tags:")
    if top_tags:
        for item in top_tags:
            print(f"  - {item['tag']} ({item['count']})")
    else:
        print("  - none")
    if helper_warning:
        print("Warning: Obsidian printed macOS helper-app warnings during the dashboard run.")


def _review_data(vault_dir: Path, *, tags_limit: int, unresolved_limit: int, recent_limit: int) -> dict:
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
            f"{dashboard['unresolved_links']} unresolved {_pluralize(dashboard['unresolved_links'], 'link')} {_be_verb(dashboard['unresolved_links'])} still present."
        )
    if dashboard["raw_inbox_items"] > 0:
        flags.append(
            f"{dashboard['raw_inbox_items']} raw intake {_pluralize(dashboard['raw_inbox_items'], 'item')} {_be_verb(dashboard['raw_inbox_items'])} waiting for promotion review."
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
        if dashboard["active_scope_orphans"] == 0:
            flags.append(
                f"{dashboard['orphans']} {_pluralize(dashboard['orphans'], 'note')} {_be_verb(dashboard['orphans'])} missing inbound links in Obsidian's full-vault graph, but the active note-management scope is clean."
            )
        else:
            flags.append(
                f"{dashboard['orphans']} {_pluralize(dashboard['orphans'], 'note')} {_be_verb(dashboard['orphans'])} missing inbound links in the full-vault graph."
            )
    if dashboard["deadends"] > 0 and dashboard["active_scope_deadends"] == 0:
        flags.append(
            f"{dashboard['deadends']} {_pluralize(dashboard['deadends'], 'note')} {_be_verb(dashboard['deadends'])} showing as dead ends in Obsidian's full-vault graph, but the active note-management scope is clean."
        )
    review["flags"] = flags
    return review


def _review(vault_dir: Path, *, json_output: bool, tags_limit: int, unresolved_limit: int, recent_limit: int) -> None:
    review = _review_data(
        vault_dir,
        tags_limit=tags_limit,
        unresolved_limit=unresolved_limit,
        recent_limit=recent_limit,
    )

    if json_output:
        print(json.dumps(review, indent=2))
        return

    doctor = review["doctor"]
    dashboard = review["dashboard"]
    top_unresolved = review["top_unresolved_links"]
    recent_files = review["recent_files"]

    print("Vault review")
    print(f"Vault: {doctor['vault_name']}")
    print(f"Path: {doctor['vault_dir']}")
    print(f"Version: {doctor['version']}")
    print("CLI ready: yes")
    print(f"Files: {dashboard['files']}")
    print(f"Folders: {dashboard['folders']}")
    print(f"Raw intake items: {dashboard['raw_inbox_items']}")
    print(f"Curated inbox notes: {dashboard['inbox_notes']}")
    print(f"Draft notes: {dashboard['draft_notes']}")
    print(f"Full-vault orphans: {dashboard['orphans']}")
    print(f"Full-vault dead ends: {dashboard['deadends']}")
    print(f"Active-scope notes: {dashboard['active_scope_notes']}")
    print(f"Active-scope orphans: {dashboard['active_scope_orphans']}")
    print(f"Active-scope dead ends: {dashboard['active_scope_deadends']}")
    print(f"Unresolved links: {dashboard['unresolved_links']}")
    print(f"Open tasks: {review['tasks']['todo']}")
    print(f"Done tasks: {review['tasks']['done']}")
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
    if review["flags"]:
        for flag in review["flags"]:
            print(f"  - {flag}")
    else:
        print("  - No obvious cleanup flags.")
    if review["helper_warning_seen"]:
        print("Warning: Obsidian printed macOS helper-app warnings, but review commands still completed successfully.")


def _simplify_review_data(
    vault_dir: Path,
    *,
    output_relative: Path,
    tags_limit: int,
    unresolved_limit: int,
    recent_limit: int,
    dedupe_limit: int,
    hotspot_limit: int,
    tldr_max_line: int,
) -> dict:
    review = _review_data(
        vault_dir,
        tags_limit=tags_limit,
        unresolved_limit=unresolved_limit,
        recent_limit=recent_limit,
    )
    audit = _audit_data(vault_dir, tldr_max_line=tldr_max_line)
    analysis = _structure_analysis(vault_dir, exclude_relative=output_relative)
    structure = _structure_report_data(
        vault_dir,
        output_relative=output_relative,
        limit=dedupe_limit,
        hotspot_limit=hotspot_limit,
        analysis=analysis,
    )
    basename_duplicates = _duplicate_basename_groups(analysis["note_paths_list"])
    alias_duplicates = _duplicate_alias_groups(vault_dir, analysis["note_paths_list"])

    flags: list[str] = []
    for flag in review["flags"]:
        if (
            "missing inbound links in the full-vault graph" in flag
            and structure["counts"]["orphans"] == 0
            and structure["counts"]["isolated"] == 0
        ):
            flags.append(
                f"{review['dashboard']['orphans']} {_pluralize(review['dashboard']['orphans'], 'note')} {_be_verb(review['dashboard']['orphans'])} missing inbound links in Obsidian's full-vault graph, but the active simplify-review scope is clean."
            )
            continue
        flags.append(flag)

    for flag in audit["flags"]:
        if "unresolved link" in flag.lower() and review["dashboard"]["unresolved_links"] > 0:
            continue
        flags.append(flag)
    if structure["counts"]["orphans"] > 0:
        flags.append(
            f"{structure['counts']['orphans']} active-scope {_pluralize(structure['counts']['orphans'], 'note')} {_be_verb(structure['counts']['orphans'])} still orphaned."
        )
    if structure["counts"]["deadends"] > 0:
        flags.append(
            f"{structure['counts']['deadends']} active-scope {_pluralize(structure['counts']['deadends'], 'note')} {_be_verb(structure['counts']['deadends'])} still dead ends."
        )
    if basename_duplicates:
        flags.append(
            f"{len(basename_duplicates)} duplicate basename {_pluralize(len(basename_duplicates), 'group')} {_be_verb(len(basename_duplicates))} worth manual merge review."
        )
    if alias_duplicates:
        flags.append(
            f"{len(alias_duplicates)} duplicate alias {_pluralize(len(alias_duplicates), 'group')} {_be_verb(len(alias_duplicates))} could confuse search and wikilink resolution."
        )
    deduped_flags = list(dict.fromkeys(flags))

    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "output_path": output_relative.as_posix(),
        "review": review,
        "audit": audit,
        "structure": structure,
        "dedupe": {
            "scope_notes": len(analysis["note_paths_list"]),
            "basename_duplicates": basename_duplicates,
            "alias_duplicates": alias_duplicates,
            "basename_groups": len(basename_duplicates),
            "alias_groups": len(alias_duplicates),
            "alias_scan_enabled": yaml is not None,
        },
        "workflow": {
            "raw_inbox_paths": list(review["dashboard"].get("raw_inbox_paths", [])),
            "inbox_paths": list(review["dashboard"].get("inbox_paths", [])),
            "draft_paths": list(review["dashboard"].get("draft_paths", [])),
        },
        "flags": deduped_flags,
        "ok": not deduped_flags,
    }


def _simplify_review_markdown(data: dict, *, dedupe_limit: int) -> str:
    review = data["review"]
    audit = data["audit"]
    structure = data["structure"]
    dedupe = data["dedupe"]
    doctor = review["doctor"]
    dashboard = review["dashboard"]

    lines = [
        "# Vault Simplify and Dedupe Review",
        "",
        "## TL;DR",
        f"- Vault review generated on **{data['generated_at']}** for **{doctor['vault_name']}**.",
        f"- Health snapshot: **{dashboard['unresolved_links']}** unresolved links, **{len(audit['issues']['missing_tldr'])}** notes missing `## TL;DR`, and **{structure['counts']['orphans']} / {structure['counts']['deadends']} / {structure['counts']['isolated']}** active-scope orphan/dead-end/isolated notes.",
        f"- Intake snapshot: **{dashboard['raw_inbox_items']}** raw intake items in `{dashboard['raw_inbox_path']}`, **{dashboard['curated_inbox_notes']}** curated inbox notes in `{INBOX_DIR}`, and **{dashboard['draft_notes']}** drafts in `{DRAFTS_DIR}`.",
        f"- Dedupe snapshot: **{dedupe['basename_groups']}** duplicate basename groups and **{dedupe['alias_groups']}** duplicate alias groups across **{dedupe['scope_notes']}** active notes.",
        f"- Readability snapshot: **{len(audit['issues']['oversized_overviews'])}** oversized overviews and **{len(audit['issues']['cleanup_inbox_backlog'])}** project MOCs with cleanup backlog.",
        f"- Treat this as a snapshot report under {_structure_note_link(SNAPSHOT_REPORT_CONTRACT, display='Vault Snapshot Report Contract')}. Use {_structure_note_link(VAULT_EXCEPTION_DASHBOARD, display='Vault Exception Dashboard')} or {_structure_note_link(WEEKLY_REVIEW_RUNBOOK, display='Weekly Vault Review Runbook')} for the live review sequence.",
        "",
        "## Scope",
        "",
        f"- Generated on **{data['generated_at']}** for **{doctor['vault_name']}**.",
        "- Snapshot of active-note health, duplicate-name hotspots, and readability risks.",
        "- This note summarizes the current state and highest-value follow-up items. It does not replace the live review surfaces.",
        "",
        "## Snapshot Summary",
        "",
        f"- Files: **{dashboard['files']}**",
        f"- Folders: **{dashboard['folders']}**",
        f"- Raw intake items: **{dashboard['raw_inbox_items']}**",
        f"- Curated inbox notes: **{dashboard['curated_inbox_notes']}**",
        f"- Draft notes: **{dashboard['draft_notes']}**",
        f"- Open tasks: **{review['tasks']['todo']}**",
        f"- Done tasks: **{review['tasks']['done']}**",
        "",
        "## Hotspots",
    ]
    if data["flags"]:
        lines.append("")
        for flag in data["flags"]:
            lines.append(f"- {flag}")
    else:
        lines.extend(["", "- No simplify or dedupe flags detected."])

    def _append_duplicate_table(title: str, groups: list[dict[str, object]], *, label: str) -> None:
        if not groups:
            return
        lines.extend([
            "",
            f"### {title}",
            f"| {label} | Count | Notes |",
            "| --- | ---: | --- |",
        ])
        for group in groups[:dedupe_limit]:
            links = "<br/>".join(str(link) for link in group["links"])
            lines.append(f"| `{group['value']}` | {group['count']} | {links} |")

    _append_duplicate_table("Duplicate File Names", dedupe["basename_duplicates"], label="Basename")
    if dedupe["alias_scan_enabled"]:
        _append_duplicate_table("Duplicate Aliases", dedupe["alias_duplicates"], label="Alias")
    else:
        lines.extend([
            "",
            "- Duplicate alias scan skipped because `PyYAML` is not available locally.",
        ])

    oversized_overviews = audit["issues"]["oversized_overviews"]
    if oversized_overviews:
        lines.extend([
            "",
            "### Readability Hotspots",
            "",
            "#### Oversized Overviews",
            "| Overview | Lines |",
            "| --- | ---: |",
        ])
        for item in oversized_overviews:
            lines.append(f"| {_structure_note_link(Path(str(item['path'])))} | {item['lines']} |")

    cleanup_backlog = audit["issues"]["cleanup_inbox_backlog"]
    if cleanup_backlog:
        if not oversized_overviews:
            lines.extend([
                "",
                "### Readability Hotspots",
            ])
        lines.extend([
            "",
            "#### Cleanup Inbox Backlog",
            "| Overview | Pending Entries |",
            "| --- | ---: |",
        ])
        for item in cleanup_backlog:
            lines.append(f"| {_structure_note_link(Path(str(item['path'])))} | {item['count']} |")

    lines.extend([
        "",
        "## Suggested Actions",
        "- Use this report as the first pass. Resolve policy failures and unresolved links before merging or renaming note content.",
        f"- Treat any `_Overview.md` above {OVERVIEW_MAX_LINES} lines as an index split candidate. Move deep status history or long validation logs into child notes.",
        "- Empty `Structure Cleanup Inbox` sections after each cleanup pass. A stale inbox means the MOC has become a second backlog instead of a map.",
        "- Review duplicate basename groups next. If two notes represent the same concept, choose one canonical location and convert the other into a redirect, merge, or archive candidate.",
        "- Review duplicate aliases last. Keep a single canonical alias per concept so search and wikilinks stay predictable.",
        "",
        "## Related",
        f"- {_structure_note_link(STRUCTURE_ROOT_HUB, display='Vault Operations Index')}",
        f"- {_structure_note_link(SNAPSHOT_REPORT_CONTRACT, display='Vault Snapshot Report Contract')}",
        f"- {_structure_note_link(VAULT_EXCEPTION_DASHBOARD, display='Vault Exception Dashboard')}",
        f"- {_structure_note_link(WEEKLY_REVIEW_RUNBOOK, display='Weekly Vault Review Runbook')}",
        f"- {_structure_note_link(Path(STRUCTURE_REPORT_DEFAULT), display='Vault Structure Cleanup Report')}",
        "",
    ])
    return "\n".join(lines)


def _simplify_review(
    vault_dir: Path,
    *,
    json_output: bool,
    dry_run: bool,
    tags_limit: int,
    unresolved_limit: int,
    recent_limit: int,
    dedupe_limit: int,
    hotspot_limit: int,
    tldr_max_line: int,
    output_path: str,
) -> None:
    output_relative = _normalize_relative_path(output_path, label="Output path")
    data = _simplify_review_data(
        vault_dir,
        output_relative=output_relative,
        tags_limit=tags_limit,
        unresolved_limit=unresolved_limit,
        recent_limit=recent_limit,
        dedupe_limit=dedupe_limit,
        hotspot_limit=hotspot_limit,
        tldr_max_line=tldr_max_line,
    )
    if json_output:
        print(json.dumps(data, indent=2))
        return

    report_text = _simplify_review_markdown(data, dedupe_limit=dedupe_limit)
    output_abs = vault_dir / output_relative
    if not dry_run:
        output_abs.parent.mkdir(parents=True, exist_ok=True)
        output_abs.write_text(report_text, encoding="utf-8")

    print("Vault simplify review")
    print(f"Vault: {data['review']['doctor']['vault_name']}")
    print(f"Path: {data['review']['doctor']['vault_dir']}")
    print(f"Files: {data['review']['dashboard']['files']}")
    print(f"Folders: {data['review']['dashboard']['folders']}")
    print(f"Unresolved links: {data['review']['dashboard']['unresolved_links']}")
    print(f"Missing TL;DR: {len(data['audit']['issues']['missing_tldr'])}")
    print(f"Active-scope orphans: {data['structure']['counts']['orphans']}")
    print(f"Active-scope dead ends: {data['structure']['counts']['deadends']}")
    print(f"Oversized overviews: {len(data['audit']['issues']['oversized_overviews'])}")
    print(f"Cleanup backlog overviews: {len(data['audit']['issues']['cleanup_inbox_backlog'])}")
    print(f"Duplicate basename groups: {data['dedupe']['basename_groups']}")
    print(f"Duplicate alias groups: {data['dedupe']['alias_groups']}")
    print("Flags:")
    if data["flags"]:
        for flag in data["flags"]:
            print(f"  - {flag}")
    else:
        print("  - No simplify or dedupe issues detected.")
    if dry_run:
        print(f"Would write report: {output_relative.as_posix()}")
    else:
        print(f"Wrote report: {output_relative.as_posix()}")


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
    oversized_overviews: list[dict[str, int | str]] = []
    cleanup_inbox_backlog: list[dict[str, int | str]] = []
    frontmatter_files_checked = 0
    tldr_files_checked = 0
    overview_files_checked = 0

    for relative_path in markdown_files:
        path = vault_dir / relative_path
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            file_read_errors.append({"path": relative_path.as_posix(), "error": str(exc)})
            continue

        lines = text.splitlines()
        if relative_path.name == "_Overview.md":
            overview_files_checked += 1
            if len(lines) > OVERVIEW_MAX_LINES:
                oversized_overviews.append({"path": relative_path.as_posix(), "lines": len(lines)})
            cleanup_count = _structure_cleanup_inbox_count(lines)
            if cleanup_count > 0:
                cleanup_inbox_backlog.append({"path": relative_path.as_posix(), "count": cleanup_count})
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
            "overview_files_checked": overview_files_checked,
            "tldr_max_line": tldr_max_line,
        },
        "issues": {
            "missing_required_folders": missing_required_folders,
            "missing_project_overviews": missing_project_overviews,
            "file_read_errors": file_read_errors,
            "frontmatter_errors": frontmatter_errors,
            "missing_tldr": missing_tldr,
            "late_tldr": late_tldr,
            "oversized_overviews": oversized_overviews,
            "cleanup_inbox_backlog": cleanup_inbox_backlog,
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
    if oversized_overviews:
        flags.append(
            f"{len(oversized_overviews)} project {_pluralize(len(oversized_overviews), '_Overview.md')} {_be_verb(len(oversized_overviews))} over {OVERVIEW_MAX_LINES} lines and should be split or trimmed."
        )
    if cleanup_inbox_backlog:
        cleanup_total = sum(int(item["count"]) for item in cleanup_inbox_backlog)
        flags.append(
            f"{len(cleanup_inbox_backlog)} project {_pluralize(len(cleanup_inbox_backlog), '_Overview.md')} {_be_verb(len(cleanup_inbox_backlog))} still carrying {cleanup_total} pending Structure Cleanup Inbox {_pluralize(cleanup_total, 'item')}."
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
    print(f"Overview files checked: {summary['overview_files_checked']}")
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
    _print_samples("Oversized overviews", issues["oversized_overviews"], limit=limit)
    _print_samples("Cleanup inbox backlog", issues["cleanup_inbox_backlog"], limit=limit)
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


def _structure_fix(vault_dir: Path, *, dry_run: bool, limit: int) -> None:
    analysis = _structure_analysis(vault_dir, exclude_relative=Path(STRUCTURE_REPORT_DEFAULT))
    deadend_candidates = [
        path
        for path in analysis["deadends"]
        if analysis["overview_map"].get(path) is not None
    ]
    hub_note_groups: dict[Path, list[Path]] = defaultdict(list)
    for path in sorted(set(analysis["orphans"]) | set(analysis["deadends"])):
        hub = _fallback_hub_for_path(path)
        if hub is not None:
            hub_note_groups[hub].append(path)
    orphan_groups: dict[Path, list[Path]] = defaultdict(list)
    for path in analysis["orphans"]:
        overview = analysis["overview_map"].get(path)
        if overview is not None:
            orphan_groups[overview].append(path)
    hub_backlink_candidates = sorted(
        {
            note_path.as_posix()
            for hub_path, note_paths in hub_note_groups.items()
            for note_path in note_paths
            if not _skip_hub_backlink(note_path)
        }
    )

    planned_note_updates: list[str] = []
    planned_overview_updates: list[str] = []
    planned_hub_updates: list[str] = []

    if not dry_run:
        for path in deadend_candidates:
            overview = analysis["overview_map"][path]
            note_abs = vault_dir / path
            text = note_abs.read_text(encoding="utf-8")
            updated_text, changed = _ensure_related_overview_link(text, overview)
            if changed:
                note_abs.write_text(updated_text, encoding="utf-8")
                planned_note_updates.append(path.as_posix())

        for overview, note_paths in sorted(orphan_groups.items(), key=lambda item: item[0].as_posix()):
            overview_abs = vault_dir / overview
            text = overview_abs.read_text(encoding="utf-8")
            updated_text, changed = _ensure_overview_cleanup_links(text, note_paths)
            if changed:
                overview_abs.write_text(updated_text, encoding="utf-8")
                planned_overview_updates.append(overview.as_posix())

        for hub_path, note_paths in sorted(hub_note_groups.items(), key=lambda item: item[0].as_posix()):
            hub_abs = vault_dir / hub_path
            hub_abs.parent.mkdir(parents=True, exist_ok=True)
            hub_abs.write_text(_hub_note_markdown(hub_path, note_paths), encoding="utf-8")
            planned_hub_updates.append(hub_path.as_posix())

        for hub_path, note_paths in sorted(hub_note_groups.items(), key=lambda item: item[0].as_posix()):
            for note_path in note_paths:
                if _skip_hub_backlink(note_path):
                    continue
                note_abs = vault_dir / note_path
                text = note_abs.read_text(encoding="utf-8")
                updated_text, changed = _ensure_related_link(text, hub_path, display=_hub_title(hub_path))
                if changed:
                    note_abs.write_text(updated_text, encoding="utf-8")
                    if note_path.as_posix() not in planned_note_updates:
                        planned_note_updates.append(note_path.as_posix())
    else:
        planned_note_updates = sorted({path.as_posix() for path in deadend_candidates} | set(hub_backlink_candidates))
        planned_overview_updates = [path.as_posix() for path in sorted(orphan_groups)]
        planned_hub_updates = [path.as_posix() for path in sorted(hub_note_groups)]

    print(f"Dead-end notes with overview candidates: {len(deadend_candidates)}")
    print(f"Overview files with orphan note candidates: {len(orphan_groups)}")
    print(f"Fallback hub notes: {len(hub_note_groups)}")
    action_label = "Would update note links" if dry_run else "Updated note links"
    print(f"{action_label}: {len(planned_note_updates)}")
    if planned_note_updates:
        for path in planned_note_updates[:limit]:
            print(f"  - {path}")
        remaining = len(planned_note_updates) - limit
        if remaining > 0:
            print(f"  - ... {remaining} more")
    action_label = "Would update overviews" if dry_run else "Updated overviews"
    print(f"{action_label}: {len(planned_overview_updates)}")
    if planned_overview_updates:
        for path in planned_overview_updates[:limit]:
            print(f"  - {path}")
        remaining = len(planned_overview_updates) - limit
        if remaining > 0:
            print(f"  - ... {remaining} more")
    action_label = "Would update hubs" if dry_run else "Updated hubs"
    print(f"{action_label}: {len(planned_hub_updates)}")
    if planned_hub_updates:
        for path in planned_hub_updates[:limit]:
            print(f"  - {path}")


def _archive_fix(vault_dir: Path, *, dry_run: bool, limit: int) -> None:
    archive_notes = _iter_archive_markdown_files(vault_dir)
    index_groups: dict[Path, list[Path]] = defaultdict(list)
    for note_path in archive_notes:
        index_path = _archive_index_for_note(vault_dir, note_path)
        if index_path is not None:
            index_groups[index_path].append(note_path)

    planned_note_updates: list[str] = []
    planned_index_updates: list[str] = []

    if not dry_run:
        for index_path, note_paths in sorted(index_groups.items(), key=lambda item: item[0].as_posix()):
            index_abs = vault_dir / index_path
            if not index_abs.exists():
                index_abs.parent.mkdir(parents=True, exist_ok=True)
                index_abs.write_text(_archive_index_markdown(vault_dir, index_path, note_paths), encoding="utf-8")
                planned_index_updates.append(index_path.as_posix())

        for index_path, note_paths in sorted(index_groups.items(), key=lambda item: item[0].as_posix()):
            for note_path in note_paths:
                note_abs = vault_dir / note_path
                text = note_abs.read_text(encoding="utf-8")
                updated_text, changed = _ensure_related_link(text, index_path, display="Archive Index")
                if changed:
                    note_abs.write_text(updated_text, encoding="utf-8")
                    planned_note_updates.append(note_path.as_posix())
    else:
        planned_index_updates = [
            index_path.as_posix()
            for index_path in sorted(index_groups)
            if not (vault_dir / index_path).exists()
        ]
        planned_note_updates = [
            note_path.as_posix()
            for note_path in sorted(archive_notes, key=lambda p: p.as_posix())
            if _archive_index_for_note(vault_dir, note_path) is not None
        ]

    print(f"Archive notes scanned: {len(archive_notes)}")
    print(f"Archive indexes targeted: {len(index_groups)}")
    action_label = "Would update archive notes" if dry_run else "Updated archive notes"
    print(f"{action_label}: {len(planned_note_updates)}")
    if planned_note_updates:
        for path in planned_note_updates[:limit]:
            print(f"  - {path}")
        remaining = len(planned_note_updates) - limit
        if remaining > 0:
            print(f"  - ... {remaining} more")
    action_label = "Would create archive indexes" if dry_run else "Created archive indexes"
    print(f"{action_label}: {len(planned_index_updates)}")
    if planned_index_updates:
        for path in planned_index_updates[:limit]:
            print(f"  - {path}")


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


def _capture_raw_note(
    vault_dir: Path,
    *,
    title: str,
    folder: str,
    name: str | None,
    body: str | None,
    source: str | None,
    extension: str,
    overwrite: bool,
    dry_run: bool,
) -> None:
    target_folder, relative_folder = _resolve_vault_path(
        vault_dir,
        folder,
        label="Raw target folder",
        must_exist=True,
        expect_directory=True,
    )
    if not relative_folder.startswith(f"{RAW_SUBMODULE_DIR}/") and relative_folder != RAW_SUBMODULE_DIR:
        _die(f'Raw capture must stay inside "{RAW_SUBMODULE_DIR}/": {relative_folder}')
    normalized_extension = extension.strip().lstrip(".").lower() or "md"
    file_name = _normalize_note_name(name) if name else _slugify(title)
    relative_path = f"{relative_folder}/{file_name}.{normalized_extension}"
    lines: list[str]
    if normalized_extension == "md":
        lines = [f"# {title}", ""]
        if source:
            lines.extend(["Source: " + source.strip(), ""])
        if body:
            lines.extend([body.strip(), ""])
    else:
        lines = []
        if source:
            lines.append("Source: " + source.strip())
        if body:
            if lines:
                lines.append("")
            lines.append(body.strip())
    content = "\n".join(lines).rstrip() + "\n"
    destination = target_folder / f"{file_name}.{normalized_extension}"
    if destination.exists() and not overwrite:
        _die(f"Raw note already exists: {destination}")
    if dry_run:
        print(f"Would create raw file: {relative_path}")
        return
    destination.write_text(content, encoding="utf-8")
    print(f"Created raw file: {relative_path}")


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

    simplify_review_parser = subparsers.add_parser(
        "simplify-review",
        help="Run an all-in-one simplify and dedupe review across vault health, structure, and duplicate notes",
    )
    simplify_review_parser.add_argument("--json", action="store_true", help="Output JSON instead of markdown")
    simplify_review_parser.add_argument("--dry-run", action="store_true", help="Print the summary without writing the note")
    simplify_review_parser.add_argument("--tags-limit", type=int, default=10, help="Number of top tags to include")
    simplify_review_parser.add_argument(
        "--unresolved-limit",
        type=int,
        default=10,
        help="Number of unresolved links to include",
    )
    simplify_review_parser.add_argument(
        "--recent-limit",
        type=int,
        default=10,
        help="Number of recent files to include",
    )
    simplify_review_parser.add_argument(
        "--dedupe-limit",
        type=int,
        default=12,
        help="Number of duplicate groups to include in the markdown report",
    )
    simplify_review_parser.add_argument(
        "--hotspot-limit",
        type=int,
        default=10,
        help="Number of hotspot folders to include",
    )
    simplify_review_parser.add_argument(
        "--tldr-max-line",
        type=int,
        default=40,
        help="Maximum number of lines after frontmatter for the TL;DR heading to count as near the top",
    )
    simplify_review_parser.add_argument(
        "--output-path",
        default=SIMPLIFY_REVIEW_DEFAULT,
        help=f"Vault-relative markdown report path. Default: {SIMPLIFY_REVIEW_DEFAULT}",
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

    structure_fix_parser = subparsers.add_parser(
        "structure-fix",
        help="Apply high-confidence structure fixes using local project overviews",
    )
    structure_fix_parser.add_argument("--dry-run", action="store_true", help="List planned updates without editing files")
    structure_fix_parser.add_argument(
        "--limit",
        type=int,
        default=12,
        help="Number of sample file paths to print",
    )

    archive_fix_parser = subparsers.add_parser(
        "archive-fix",
        help="Create missing archive indexes and add backlink anchors for archived notes",
    )
    archive_fix_parser.add_argument("--dry-run", action="store_true", help="List planned updates without editing files")
    archive_fix_parser.add_argument(
        "--limit",
        type=int,
        default=12,
        help="Number of sample file paths to print",
    )

    capture_parser = subparsers.add_parser("capture", help="Create a new note in Inbox or another folder")
    capture_parser.add_argument("title", help="Human title for the note")
    capture_parser.add_argument("--folder", default=INBOX_DIR, help=f"Target folder. Default: {INBOX_DIR}")
    capture_parser.add_argument("--name", default=None, help="Optional file name override")
    capture_parser.add_argument("--body", default=None, help="Optional intro paragraph")
    capture_parser.add_argument("--overwrite", action="store_true", help="Overwrite an existing note")
    capture_parser.add_argument("--sync", action="store_true", help="Run git sync after creation")
    capture_parser.add_argument("--dry-run", action="store_true", help="Print the planned path only")

    capture_raw_parser = subparsers.add_parser("capture-raw", help='Create a raw source file inside the raw submodule')
    capture_raw_parser.add_argument("title", help="Human title for the raw item")
    capture_raw_parser.add_argument("--folder", default=f"{RAW_SUBMODULE_DIR}/inbox", help=f'Target folder. Default: "{RAW_SUBMODULE_DIR}/inbox"')
    capture_raw_parser.add_argument("--name", default=None, help="Optional file name override")
    capture_raw_parser.add_argument("--body", default=None, help="Optional body text")
    capture_raw_parser.add_argument("--source", default=None, help="Optional source URL or citation line")
    capture_raw_parser.add_argument("--extension", default="md", help='File extension for the raw item. Default: "md"')
    capture_raw_parser.add_argument("--overwrite", action="store_true", help="Overwrite an existing raw file")
    capture_raw_parser.add_argument("--dry-run", action="store_true", help="Print the planned path only")

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

    if args.command == "simplify-review":
        _simplify_review(
            vault_dir,
            json_output=args.json,
            dry_run=args.dry_run,
            tags_limit=args.tags_limit,
            unresolved_limit=args.unresolved_limit,
            recent_limit=args.recent_limit,
            dedupe_limit=args.dedupe_limit,
            hotspot_limit=args.hotspot_limit,
            tldr_max_line=args.tldr_max_line,
            output_path=args.output_path,
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

    if args.command == "structure-fix":
        _structure_fix(
            vault_dir,
            dry_run=args.dry_run,
            limit=args.limit,
        )
        return

    if args.command == "archive-fix":
        _archive_fix(
            vault_dir,
            dry_run=args.dry_run,
            limit=args.limit,
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

    if args.command == "capture-raw":
        _capture_raw_note(
            vault_dir,
            title=args.title,
            folder=args.folder,
            name=args.name,
            body=args.body,
            source=args.source,
            extension=args.extension,
            overwrite=args.overwrite,
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
