#!/usr/bin/env python3
"""Always-on context budget lines for --status. No secrets.

Skill counts here are a static installed-file inventory, not the live
discovered set and not the model-visible prompt. Description tokens are a
coarse UTF-8 bytes/4 estimate, not a tokenizer count.

Does not run the grok CLI and does not print API keys, URLs, headers,
env_key values, or skill description text.
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

STATIC_TOKEN_ESTIMATE = "description tokens = UTF-8 bytes / 4 (coarse estimate)"
SKIP_PARTS = {"node_modules", ".git", "archive", "dist"}
FRONTMATTER_KEYS = ("name", "description")
BLOCK_SCALARS = (">", ">-", ">+", "|", "|-", "|+")


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


def _strip_bom(text: str) -> str:
    return text[1:] if text.startswith("\ufeff") else text


def _unquote(raw: str) -> str:
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        return raw[1:-1]
    return raw


def parse_skill_frontmatter(text: str) -> dict[str, str]:
    """Top-level name/description from SKILL.md frontmatter.

    Handles BOM, CRLF, quoted and plain same-line values, plain scalar
    continuations, and folded/literal block scalars. Returns {} when no
    closed frontmatter block is present.
    """
    lines = _strip_bom(text).splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    end = None
    for index in range(1, len(lines)):
        if lines[index].strip() in ("---", "..."):
            end = index
            break
    if end is None:
        return {}
    block = lines[1:end]
    data: dict[str, str] = {}
    index = 0
    while index < len(block):
        line = block[index]
        if not line.strip() or line.lstrip().startswith("#"):
            index += 1
            continue
        if line[:1].isspace() or ":" not in line:
            index += 1
            continue
        key, raw = line.split(":", 1)
        key = key.strip()
        if key not in FRONTMATTER_KEYS:
            index += 1
            continue
        raw = raw.strip()
        if raw in BLOCK_SCALARS:
            folded = raw.startswith(">")
            parts: list[str] = []
            index += 1
            while index < len(block):
                follow = block[index]
                if not follow.strip():
                    parts.append("")
                    index += 1
                    continue
                if not follow[:1].isspace():
                    break
                parts.append(follow.strip())
                index += 1
            while parts and not parts[-1]:
                parts.pop()
            while parts and not parts[0]:
                parts.pop(0)
            if folded:
                value = re.sub(r"[ \t]+", " ", " ".join(part for part in parts if part)).strip()
            else:
                value = "\n".join(parts).strip()
            data[key] = value
            continue
        if raw[:1] in ("'", '"'):
            quote = raw[0]
            if len(raw) >= 2 and raw[-1] == quote:
                data[key] = raw[1:-1]
                index += 1
                continue
            parts = [raw[1:]]
            index += 1
            while index < len(block):
                follow = block[index].strip()
                if follow.endswith(quote):
                    parts.append(follow[:-1])
                    index += 1
                    break
                parts.append(follow)
                index += 1
            data[key] = " ".join(part for part in parts if part)
            continue
        parts = [raw]
        index += 1
        while index < len(block):
            follow = block[index]
            if not follow.strip() or not follow[:1].isspace():
                break
            parts.append(follow.strip())
            index += 1
        data[key] = re.sub(r"[ \t]+", " ", " ".join(part for part in parts if part)).strip()
    return data


def skill_records(root: Path) -> list[dict[str, object]]:
    """One record per SKILL.md under root, in deterministic path order.

    Names and description sizes only; paths and text never leave this module.
    """
    if not root.is_dir():
        return []
    records: list[dict[str, object]] = []
    for skill in sorted(root.rglob("SKILL.md"), key=lambda path: path.as_posix()):
        if any(part in SKIP_PARTS for part in skill.parts):
            continue
        try:
            text = skill.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        meta = parse_skill_frontmatter(text)
        name = _unquote(meta.get("name", "")) or skill.parent.name
        desc = meta.get("description", "")
        records.append(
            {
                "name": name,
                "description_chars": len(desc),
                "description_tokens": tok_of(desc),
            }
        )
    return records


def catalog_summary(root: Path) -> dict[str, object]:
    """Static installed-file totals. Every file row contributes to the estimate."""
    records = skill_records(root)
    by_name: dict[str, list[dict[str, object]]] = {}
    for record in records:
        by_name.setdefault(str(record["name"]), []).append(record)
    duplicates = [
        {"name": name, "count": len(rows)}
        for name, rows in sorted(by_name.items())
        if len(rows) > 1
    ]
    unique_chars = sum(int(rows[0]["description_chars"]) for _, rows in sorted(by_name.items()))
    unique_tokens = sum(int(rows[0]["description_tokens"]) for _, rows in sorted(by_name.items()))
    return {
        "skill_files": len(records),
        "unique_names": len(by_name),
        "duplicate_rows": len(records) - len(by_name),
        "duplicate_name_groups": duplicates,
        "description_chars": sum(int(record["description_chars"]) for record in records),
        "description_tokens": sum(int(record["description_tokens"]) for record in records),
        "unique_description_chars": unique_chars,
        "unique_description_tokens": unique_tokens,
        "token_estimate": STATIC_TOKEN_ESTIMATE,
    }


def skill_catalog(root: Path) -> tuple[int, int]:
    """Installed SKILL.md file count and summed description tokens."""
    summary = catalog_summary(root)
    return int(summary["skill_files"]), int(summary["description_tokens"])


def grok_mcp_servers(config: Path) -> list[str]:
    if not config.is_file():
        return []
    try:
        text = config.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    names: list[str] = []
    seen: set[str] = set()
    for match in re.finditer(r"^\[mcp_servers\.([^\]]+)\]", text, re.M):
        raw = match.group(1)
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
        count = file_tok(grok_home / rel)
        if count is None:
            lines.append(f"context: {label} missing")
            continue
        grok_sum += count
        grok_files += 1
        lines.append(f"context: {label} {count} tok")
    lines.append(f"context: grok-files {grok_files} {grok_sum} tok")
    summary = catalog_summary(grok_home / "installed-plugins")
    lines.append(
        f"context: grok-catalog {summary['skill_files']} skills "
        f"{summary['description_tokens']} tok "
        f"(static installed-plugin inventory; enable/ignore state and non-plugin "
        f"discovery roots are not applied; {summary['unique_names']} unique names; "
        f"{summary['duplicate_rows']} duplicate-name rows; {STATIC_TOKEN_ESTIMATE})"
    )
    lines.append(
        "context: grok-discovered UNKNOWN "
        "(status never runs the live CLI; discovered and model-visible sets "
        "require harness-doctor and rendered-prompt evidence)"
    )
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
        count = file_tok(path)
        if count is None:
            lines.append(f"context: {label} missing")
            continue
        c_sum += count
        c_n += 1
        lines.append(f"context: {label} {count} tok")
    lines.append(f"context: claude-files {c_n} {c_sum} tok")
    claude_mcp = json_mcp_servers(user_home / ".claude.json")
    if not claude_mcp:
        claude_mcp = json_mcp_servers(user_home / ".claude" / "settings.json")
    lines.append(f"context: claude-mcp {len(claude_mcp)} servers")

    count = file_tok(user_home / ".codex" / "AGENTS.md")
    if count is None:
        lines.append("context: codex/AGENTS.md missing")
        lines.append("context: codex-files 0 0 tok")
    else:
        lines.append(f"context: codex/AGENTS.md {count} tok")
        lines.append(f"context: codex-files 1 {count} tok")

    count = file_tok(user_home / ".cursor" / "rules" / "reply-in-english.mdc")
    if count is None:
        lines.append("context: cursor/rules/reply-in-english.mdc missing")
        lines.append("context: cursor-files 0 0 tok")
    else:
        lines.append(f"context: cursor/rules/reply-in-english.mdc {count} tok")
        lines.append(f"context: cursor-files 1 {count} tok")
    cursor_mcp = json_mcp_servers(user_home / ".cursor" / "mcp.json")
    lines.append(f"context: cursor-mcp {len(cursor_mcp)} servers")
    return lines
