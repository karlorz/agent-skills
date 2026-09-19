#!/usr/bin/env python3
"""Always-on context budget lines for --status. No secrets.

Token estimate is UTF-8 bytes/4 (same coarse measure as a chars/4 census).
Does not print API keys, URLs, headers, or env_key values.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

GROK_ALWAYS_ON = (
    ("grok/AGENTS.md", "AGENTS.md"),
    ("grok/agentrules.md", "agentrules.md"),
    ("grok/skillwiki.md", "skillwiki.md"),
    ("grok/rules/reply-in-english.md", "rules/reply-in-english.md"),
)


def tok_of(text: str) -> int:
    if not text:
        return 0
    return max(1, (len(text.encode("utf-8")) + 3) // 4)


def file_tok(path: Path) -> int | None:
    if not path.is_file():
        return None
    try:
        return tok_of(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return None


def _skill_name_desc(text: str, fallback: str) -> tuple[str, str]:
    name, desc = fallback, ""
    if not text.startswith("---"):
        return name, desc
    parts = text.split("---", 2)
    if len(parts) < 3:
        return name, desc
    for line in parts[1].splitlines():
        raw = line.strip()
        if raw.startswith("name:"):
            name = raw.split(":", 1)[1].strip().strip('"').strip("'") or name
        elif raw.startswith("description:"):
            desc = raw.split(":", 1)[1].strip().strip('"').strip("'")
    return name, desc


def skill_catalog(root: Path) -> tuple[int, int]:
    """Unique SKILL.md count and summed description tokens under root."""
    if not root.is_dir():
        return 0, 0
    by: dict[str, int] = {}
    for skill in root.rglob("SKILL.md"):
        if any(p in skill.parts for p in ("node_modules", ".git")):
            continue
        try:
            text = skill.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        name, desc = _skill_name_desc(text, skill.parent.name)
        by[name] = tok_of(desc)
    return len(by), sum(by.values())


def grok_mcp_servers(config: Path) -> list[str]:
    if not config.is_file():
        return []
    try:
        text = config.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    names: list[str] = []
    seen: set[str] = set()
    for m in re.finditer(r"^\[mcp_servers\.([^\]]+)\]", text, re.M):
        raw = m.group(1)
        name = raw.split(".", 1)[0]
        if name in seen:
            continue
        seen.add(name)
        names.append(name)
    return names


def json_mcp_servers(path: Path) -> list[str]:
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    servers = data.get("mcpServers")
    if isinstance(servers, dict):
        return list(servers.keys())
    return []


def inventory_lines(
    grok_home: Path,
    user_home: Path,
    enabled_count: int | None,
) -> list[str]:
    lines: list[str] = []
    grok_sum = 0
    grok_files = 0
    for label, rel in GROK_ALWAYS_ON:
        n = file_tok(grok_home / rel)
        if n is None:
            lines.append(f"context: {label} missing")
            continue
        grok_sum += n
        grok_files += 1
        lines.append(f"context: {label} {n} tok")
    lines.append(f"context: grok-files {grok_files} {grok_sum} tok")
    skills, cat = skill_catalog(grok_home / "installed-plugins")
    lines.append(f"context: grok-catalog {skills} skills {cat} tok")
    if enabled_count is not None:
        lines.append(f"context: grok-plugins-enabled {enabled_count}")
    mcp = grok_mcp_servers(grok_home / "config.toml")
    lines.append(f"context: grok-mcp {len(mcp)} servers")

    claude_paths = (
        ("claude/CLAUDE.md", user_home / ".claude" / "CLAUDE.md"),
        ("claude/rules/reply-in-english.md", user_home / ".claude" / "rules" / "reply-in-english.md"),
    )
    c_sum, c_n = 0, 0
    for label, path in claude_paths:
        n = file_tok(path)
        if n is None:
            lines.append(f"context: {label} missing")
            continue
        c_sum += n
        c_n += 1
        lines.append(f"context: {label} {n} tok")
    lines.append(f"context: claude-files {c_n} {c_sum} tok")
    claude_mcp = json_mcp_servers(user_home / ".claude.json")
    if not claude_mcp:
        claude_mcp = json_mcp_servers(user_home / ".claude" / "settings.json")
    lines.append(f"context: claude-mcp {len(claude_mcp)} servers")

    n = file_tok(user_home / ".codex" / "AGENTS.md")
    if n is None:
        lines.append("context: codex/AGENTS.md missing")
        lines.append("context: codex-files 0 0 tok")
    else:
        lines.append(f"context: codex/AGENTS.md {n} tok")
        lines.append(f"context: codex-files 1 {n} tok")

    n = file_tok(user_home / ".cursor" / "rules" / "reply-in-english.mdc")
    if n is None:
        lines.append("context: cursor/rules/reply-in-english.mdc missing")
        lines.append("context: cursor-files 0 0 tok")
    else:
        lines.append(f"context: cursor/rules/reply-in-english.mdc {n} tok")
        lines.append(f"context: cursor-files 1 {n} tok")
    cursor_mcp = json_mcp_servers(user_home / ".cursor" / "mcp.json")
    lines.append(f"context: cursor-mcp {len(cursor_mcp)} servers")
    return lines
