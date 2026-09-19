#!/usr/bin/env python3
"""English-thinking rule SSOT: inventory and apply to host-native load paths.

One asset owns the prose: assets/reply-in-english.md. Each host still loads
its own file (Grok rules + AGENTS.md, Claude rules + CLAUDE.md, Codex AGENTS.md,
Cursor alwaysApply .mdc). This module copies/splices those targets and reports
missing|match|drift. No secrets.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_PLUGIN_ROOT = HERE.parent
SSOT_REL = Path("assets") / "reply-in-english.md"
USER_PREF = "## User preferences"
CURSOR_FRONTMATTER = (
    "---\n"
    "description: Think and reply in English; user language is input only\n"
    "alwaysApply: true\n"
    "---\n\n"
)

LABELS = (
    "grok/rules/reply-in-english.md",
    "grok/AGENTS.md",
    "claude/rules/reply-in-english.md",
    "claude/CLAUDE.md",
    "codex/AGENTS.md",
    "cursor/rules/reply-in-english.mdc",
)


def collapse(text: str) -> str:
    return " ".join(text.split())


def load_ssot(plugin_root: Path) -> str:
    path = plugin_root / SSOT_REL
    return path.read_text(encoding="utf-8")


def ssot_body(ssot: str) -> str:
    lines = ssot.strip().splitlines()
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    return "\n".join(lines).strip() + "\n"


def ensure_nl(text: str) -> str:
    return text if text.endswith("\n") else text + "\n"


def wrap_bullet(body: str) -> str:
    filled = textwrap.fill(
        collapse(body),
        width=78,
        initial_indent="- ",
        subsequent_indent="  ",
        break_long_words=False,
        break_on_hyphens=False,
    )
    return filled


def default_user_home(grok_home: Path) -> Path:
    return grok_home.expanduser().resolve(strict=False).parent


def find_english_bullet_range(lines: list[str]) -> tuple[int, int] | None:
    start = None
    for i, line in enumerate(lines):
        if line.startswith("- ") and "English-thinking assistant" in line:
            start = i
            break
    if start is None:
        return None
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line.startswith("- ") or line.startswith("#"):
            break
        if line.strip() == "":
            break
        if line.startswith("  "):
            end += 1
            continue
        break
    return start, end


def extract_english_bullet(text: str) -> str | None:
    rng = find_english_bullet_range(text.splitlines())
    if rng is None:
        return None
    start, end = rng
    return "\n".join(text.splitlines()[start:end])


def upsert_agents_bullet(text: str, bullet: str) -> str:
    lines = text.splitlines()
    rng = find_english_bullet_range(lines)
    bullet_lines = bullet.splitlines()
    if rng is not None:
        start, end = rng
        new_lines = lines[:start] + bullet_lines + lines[end:]
        out = "\n".join(new_lines)
        return ensure_nl(out) if text.endswith("\n") or out else ensure_nl(out)
    for i, line in enumerate(lines):
        if line.strip() == USER_PREF:
            j = i + 1
            if j < len(lines) and lines[j].strip() == "":
                j += 1
            new_lines = lines[:j] + bullet_lines + lines[j:]
            return ensure_nl("\n".join(new_lines))
    base = text.rstrip()
    if base:
        return base + "\n\n" + USER_PREF + "\n" + bullet + "\n"
    return USER_PREF + "\n" + bullet + "\n"


def _english_span(text: str) -> tuple[int, int] | None:
    start_token = "# Assistant replies stay English"
    alt = "You are an English-thinking assistant"
    idx = text.find(start_token)
    if idx < 0:
        idx = text.find(alt)
    if idx < 0:
        return None
    end_token = "Keep this until the user explicitly overrides it."
    end = text.find(end_token, idx)
    if end < 0:
        return idx, len(text)
    end = end + len(end_token)
    if end < len(text) and text[end] == "\n":
        end += 1
    return idx, end


def upsert_body_doc(text: str, ssot: str) -> str:
    ssot = ensure_nl(ssot.strip() + "\n")
    if not text.strip():
        return ssot
    if collapse(text) == collapse(ssot):
        return ssot
    span = _english_span(text)
    if span is None:
        return ssot + "\n" + ensure_nl(text.lstrip())
    start, end = span
    return ensure_nl(text[:start] + ssot.rstrip() + "\n" + text[end:].lstrip("\n"))


def cursor_text(ssot: str) -> str:
    return CURSOR_FRONTMATTER + ensure_nl(ssot.strip() + "\n")


def cursor_body(text: str) -> str:
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            return parts[2].lstrip("\n")
    return text


def classify_body(path: Path, expected: str) -> str:
    if not path.is_file():
        return "missing"
    got = path.read_text(encoding="utf-8")
    if collapse(got) == collapse(expected):
        return "match"
    return "drift"


def classify_cursor(path: Path, ssot: str) -> str:
    if not path.is_file():
        return "missing"
    got = cursor_body(path.read_text(encoding="utf-8"))
    if collapse(got) == collapse(ssot):
        return "match"
    return "drift"


def classify_agents(path: Path, body: str) -> str:
    if not path.is_file():
        return "missing"
    bullet = extract_english_bullet(path.read_text(encoding="utf-8"))
    if bullet is None:
        return "missing"
    if collapse(bullet.lstrip("- ")) == collapse(body):
        return "match"
    return "drift"


def target_paths(grok_home: Path, user_home: Path) -> dict[str, Path]:
    return {
        "grok/rules/reply-in-english.md": grok_home / "rules" / "reply-in-english.md",
        "grok/AGENTS.md": grok_home / "AGENTS.md",
        "claude/rules/reply-in-english.md": user_home / ".claude" / "rules" / "reply-in-english.md",
        "claude/CLAUDE.md": user_home / ".claude" / "CLAUDE.md",
        "codex/AGENTS.md": user_home / ".codex" / "AGENTS.md",
        "cursor/rules/reply-in-english.mdc": user_home / ".cursor" / "rules" / "reply-in-english.mdc",
    }


def inventory_lines(grok_home: Path, user_home: Path, plugin_root: Path) -> list[str]:
    ssot = load_ssot(plugin_root)
    body = ssot_body(ssot)
    paths = target_paths(grok_home, user_home)
    states = {
        "grok/rules/reply-in-english.md": classify_body(paths["grok/rules/reply-in-english.md"], ssot),
        "grok/AGENTS.md": classify_agents(paths["grok/AGENTS.md"], body),
        "claude/rules/reply-in-english.md": classify_body(paths["claude/rules/reply-in-english.md"], ssot),
        "claude/CLAUDE.md": classify_body(paths["claude/CLAUDE.md"], ssot),
        "codex/AGENTS.md": classify_agents(paths["codex/AGENTS.md"], body),
        "cursor/rules/reply-in-english.mdc": classify_cursor(paths["cursor/rules/reply-in-english.mdc"], ssot),
    }
    return [f"english_rule: {label} {states[label]}" for label in LABELS]


def _backup(path: Path, backup_dir: Path | None) -> None:
    if backup_dir is None or not path.is_file():
        return
    backup_dir.mkdir(parents=True, exist_ok=True)
    dest = backup_dir / path.name
    if dest.exists():
        dest = backup_dir / f"{path.parent.name}-{path.name}"
    shutil.copy2(path, dest)


def _write(path: Path, content: str, dry_run: bool, backup_dir: Path | None) -> str:
    content = ensure_nl(content)
    if path.is_file() and path.read_text(encoding="utf-8") == content:
        return "ok"
    if dry_run:
        return "would-write"
    if path.is_file():
        _backup(path, backup_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return "wrote"


def apply_english_rule(
    grok_home: Path,
    user_home: Path,
    plugin_root: Path,
    *,
    dry_run: bool = False,
    backup_dir: Path | None = None,
) -> list[str]:
    ssot = load_ssot(plugin_root)
    body = ssot_body(ssot)
    bullet = wrap_bullet(body)
    paths = target_paths(grok_home, user_home)
    logs: list[str] = []

    def note(label: str, action: str) -> None:
        logs.append(f"english_rule: {action} {label}")

    note("grok/rules/reply-in-english.md", _write(paths["grok/rules/reply-in-english.md"], ssot, dry_run, backup_dir))

    grok_agents = paths["grok/AGENTS.md"]
    current = grok_agents.read_text(encoding="utf-8") if grok_agents.is_file() else ""
    note("grok/AGENTS.md", _write(grok_agents, upsert_agents_bullet(current, bullet), dry_run, backup_dir))

    note(
        "claude/rules/reply-in-english.md",
        _write(paths["claude/rules/reply-in-english.md"], ssot, dry_run, backup_dir),
    )
    claude_md = paths["claude/CLAUDE.md"]
    current = claude_md.read_text(encoding="utf-8") if claude_md.is_file() else ""
    note("claude/CLAUDE.md", _write(claude_md, upsert_body_doc(current, ssot), dry_run, backup_dir))

    codex_agents = paths["codex/AGENTS.md"]
    current = codex_agents.read_text(encoding="utf-8") if codex_agents.is_file() else ""
    note("codex/AGENTS.md", _write(codex_agents, upsert_agents_bullet(current, bullet), dry_run, backup_dir))

    note(
        "cursor/rules/reply-in-english.mdc",
        _write(paths["cursor/rules/reply-in-english.mdc"], cursor_text(ssot), dry_run, backup_dir),
    )
    return logs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="English-thinking rule inventory/apply")
    parser.add_argument("--grok-home", default=os.environ.get("GROK_HOME", str(Path.home() / ".grok")))
    parser.add_argument("--user-home", default="")
    parser.add_argument("--plugin-root", default=str(DEFAULT_PLUGIN_ROOT))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--splice-agents", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--backup-dir", default="")
    args = parser.parse_args(list(sys.argv[1:] if argv is None else argv))
    grok_home = Path(args.grok_home).expanduser()
    user_home = Path(args.user_home).expanduser() if args.user_home else default_user_home(grok_home)
    plugin_root = Path(args.plugin_root).expanduser()
    if args.splice_agents:
        path = Path(args.splice_agents)
        ssot = load_ssot(plugin_root)
        bullet = wrap_bullet(ssot_body(ssot))
        current = path.read_text(encoding="utf-8") if path.is_file() else ""
        path.write_text(upsert_agents_bullet(current, bullet), encoding="utf-8")
        return 0
    if args.apply:
        backup = Path(args.backup_dir).expanduser() if args.backup_dir else None
        lines = apply_english_rule(
            grok_home, user_home, plugin_root, dry_run=args.dry_run, backup_dir=backup
        )
    else:
        lines = inventory_lines(grok_home, user_home, plugin_root)
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
