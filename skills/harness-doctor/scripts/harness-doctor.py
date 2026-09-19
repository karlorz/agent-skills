#!/usr/bin/env python3
"""Read-only cross-agent harness doctor. Never writes host config."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA = "harness-doctor.v1"
HARNESSES = ("claude", "grok", "codex", "cursor")
MIN_SESSIONS = 20
MIN_SPAN_DAYS = 7
SLOW_SESSION_START_MS = 20_000
SLOW_PER_TOOL_MS = 500
CONTEXT_HEAVY_TOKENS = 3_000
MAX_TRANSCRIPT_BYTES = 8_000_000
MAX_DETAILS = 20
CMD_TIMEOUT = 4.0

SEVERITIES = ("PASS", "INFO", "WARN", "FAIL", "UNKNOWN")

RARE_KEEP = {
    "cursor-github-marketplace-repin",
    "grok-build-harness",
    "host-backup-restore",
}
PASSIVE_NAMES = {"obsidian"}
PASSIVE_HINTS = ("theme", "output-style", "output_style", "monitor", "lsp", "workflow")
WRITE_HINTS = (
    "push",
    "commit",
    "merge",
    "rebase",
    "reset",
    "checkout",
    "rm",
    "delete",
    "write",
    "apply",
    "create",
    "install",
    "publish",
    "ssh",
    "make",
    "npm",
    "pnpm",
    "yarn",
    "pip",
    "docker",
    "kill",
    "chmod",
    "chown",
)
READ_HINTS = (
    "status",
    "log",
    "diff",
    "show",
    "ls",
    "cat",
    "head",
    "tail",
    "rg",
    "grep",
    "find",
    "view",
    "list",
    "get",
    "read",
    "stat",
    "blame",
)
SECRET_KEY_RE = re.compile(
    r"(token|secret|password|passwd|api[_-]?key|bearer|authorization|authid|auth_id|email)",
    re.I,
)
SECRET_VALUE_RE = re.compile(
    r"(?i)\b(?:sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    r"|xai-[A-Za-z0-9_-]{8,}|Bearer\s+\S+)"
)
EMAIL_RE = re.compile(r"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b", re.I)
URL_TOKEN_RE = re.compile(r"(https?://\S+[?&](?:token|key|secret|auth)=)\S+", re.I)
SLASH_RE = re.compile(r"^/([A-Za-z][A-Za-z0-9_-]{1,63})\b")
VERSION_RE = re.compile(r"\b(\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?)\b")
SKIP_JSONL_NAMES = {"journal.jsonl"}
PROMPT_KEYS = {
    "content",
    "message",
    "lastprompt",
    "snapshot",
    "encrypted_content",
    "prompt",
    "text",
    "body",
    "arguments",
    "input",
    "stdout",
    "stderr",
    "output",
}

GROK_ALWAYS_ON = (
    ("grok/AGENTS.md", "AGENTS.md"),
    ("grok/agentrules.md", "agentrules.md"),
    ("grok/skillwiki.md", "skillwiki.md"),
    ("grok/rules/reply-in-english.md", "rules/reply-in-english.md"),
)


class UsageError(Exception):
    """Bad CLI usage (exit 2)."""


class StateError(Exception):
    """Malformed required local state (exit 1)."""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


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
    if not root.is_dir():
        return 0, 0
    by: dict[str, int] = {}
    for skill in root.rglob("SKILL.md"):
        if any(part in skill.parts for part in ("node_modules", ".git")):
            continue
        try:
            text = skill.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        name, desc = _skill_name_desc(text, skill.parent.name)
        by[name] = tok_of(desc)
    return len(by), sum(by.values())


def try_load_context_budget() -> Any | None:
    sibling = (
        Path(__file__).resolve().parents[2]
        / "grok-build-harness"
        / "scripts"
        / "context_budget.py"
    )
    if not sibling.is_file():
        return None
    import importlib.util

    spec = importlib.util.spec_from_file_location("_hd_context_budget", sibling)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception:
        return None
    return mod


def _bind_context_budget() -> None:
    global tok_of, file_tok, skill_catalog, GROK_ALWAYS_ON
    budget = try_load_context_budget()
    if budget is None:
        return
    tok_of = budget.tok_of
    file_tok = budget.file_tok
    skill_catalog = budget.skill_catalog
    GROK_ALWAYS_ON = budget.GROK_ALWAYS_ON


_bind_context_budget()


def redact_text(value: str) -> str:
    text = SECRET_VALUE_RE.sub("[REDACTED]", value)
    text = URL_TOKEN_RE.sub(r"\1[REDACTED]", text)
    text = EMAIL_RE.sub("[REDACTED:email]", text)
    return text


def is_secret_key(key: str) -> bool:
    return bool(SECRET_KEY_RE.search(key))


def sanitize(value: Any, key: str = "") -> Any:
    if is_secret_key(key):
        return "[REDACTED]"
    if isinstance(value, str):
        if key.lower() in PROMPT_KEYS:
            return "[omitted]"
        return redact_text(value)
    if isinstance(value, dict):
        return {str(k): sanitize(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize(item, key) for item in value]
    return value


def dump_json(payload: Any) -> str:
    return redact_text(json.dumps(sanitize(payload), indent=2, sort_keys=True, default=str))


def sha256_file(path: Path) -> str | None:
    if not path.is_file():
        return None
    try:
        data = path.read_bytes()
    except OSError:
        return None
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path, required: bool = False) -> Any:
    if not path.is_file():
        if required:
            raise StateError(f"missing required file: {path}")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise StateError(f"malformed JSON: {path}") from exc
    except OSError as exc:
        raise StateError(f"unreadable: {path}") from exc


def read_text(path: Path) -> str | None:
    if not path.is_file():
        return None
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def which(name: str) -> str | None:
    found = shutil.which(name)
    return found if found else None


def run_cmd(argv: list[str], timeout: float = CMD_TIMEOUT) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return 127, "", ""
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def cli_version(binary: str) -> str | None:
    path = which(binary)
    if not path:
        return None
    code, out, err = run_cmd([path, "--version"])
    blob = redact_text(f"{out}\n{err}")
    match = VERSION_RE.search(blob)
    if match:
        return match.group(1)
    line = blob.strip().splitlines()[0] if blob.strip() else ""
    return line[:80] or None


def parse_details_tokens(text: str) -> int | None:
    for line in text.splitlines():
        match = re.search(r"(?i)(?:est(?:imated)?\s+)?tokens?\s*[:=]?\s*(\d+)", line)
        if match:
            return int(match.group(1))
    return None


def plugin_short(name: str) -> str:
    return name.split("@", 1)[0]


def is_passive(name: str) -> bool:
    short = plugin_short(name).lower()
    if short in PASSIVE_NAMES:
        return True
    return any(hint in short for hint in PASSIVE_HINTS)


def is_rare_keep(name: str) -> bool:
    return plugin_short(name) in RARE_KEEP


def command_key(command: str) -> str:
    parts = command.strip().split()
    if not parts:
        return "unknown"
    if len(parts) >= 2 and parts[0] in {
        "git",
        "gh",
        "npm",
        "pnpm",
        "yarn",
        "docker",
        "cargo",
        "make",
    }:
        return f"{parts[0]} {parts[1]}"
    return parts[0]


def permission_class(command: str) -> str:
    blob = command.lower()
    if any(hint in blob for hint in WRITE_HINTS):
        return "write"
    tokens = blob.replace("|", " ").split()
    if tokens and any(tokens[0].endswith(hint) or hint == tokens[0] for hint in READ_HINTS):
        return "read"
    if any(hint in blob for hint in READ_HINTS) and not any(
        hint in blob for hint in WRITE_HINTS
    ):
        return "read"
    return "unknown"


def window_sufficient(session_count: int, span_days: float) -> bool:
    return session_count >= MIN_SESSIONS and span_days >= MIN_SPAN_DAYS


def finding(
    check: str,
    severity: str,
    code: str,
    summary: str,
    evidence_kind: str,
    target: str | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    item = {
        "check": check,
        "severity": severity,
        "code": code,
        "summary": summary,
        "evidence_kind": evidence_kind,
        "reversible": True,
    }
    if target:
        item["target"] = target
    if extra:
        item["evidence"] = extra
    return item


def empty_harness(name: str, availability: str, limitation: str | None = None) -> dict[str, Any]:
    payload = {
        "name": name,
        "availability": availability,
        "version": {"value": None, "status": "UNKNOWN", "source": "unavailable"},
        "config": {},
        "extensions": {"plugins": [], "skills": [], "mcp": []},
        "usage": {"lifetime": {}, "window": {}},
        "memory": {"files": [], "duplicates": []},
        "hooks": {},
        "context": {},
        "permissions": {},
        "findings": [],
        "limitations": [],
    }
    if limitation:
        payload["limitations"].append(limitation)
    return payload


def iter_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    try:
        size = path.stat().st_size
    except OSError:
        return []
    if size > MAX_TRANSCRIPT_BYTES:
        return []
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    rows: list[dict[str, Any]] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            rows.append(obj)
    return rows


def file_mtime(path: Path) -> datetime | None:
    try:
        return datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    except OSError:
        return None


def select_files(files: list[Path], days: int, limit: int) -> tuple[list[Path], dict[str, Any]]:
    cutoff = utcnow().timestamp() - days * 86400
    dated: list[tuple[float, Path]] = []
    for path in files:
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        if mtime >= cutoff:
            dated.append((mtime, path))
    dated.sort(key=lambda item: item[0], reverse=True)
    chosen = [path for _, path in dated[:limit]]
    if not chosen:
        return [], {
            "session_count": 0,
            "span_days": 0.0,
            "sufficient": False,
            "days": days,
            "limit": limit,
        }
    newest = dated[0][0]
    oldest = min(mtime for mtime, path in dated if path in set(chosen))
    span = max(0.0, (newest - oldest) / 86400.0)
    return chosen, {
        "session_count": len(chosen),
        "span_days": round(span, 3),
        "sufficient": window_sufficient(len(chosen), span),
        "days": days,
        "limit": limit,
    }


def message_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        if "text" in value and isinstance(value["text"], str):
            return value["text"]
        return message_text(value.get("content"))
    if isinstance(value, list):
        parts = [message_text(item) for item in value]
        return "\n".join(part for part in parts if part)
    return ""


def leading_slash(text: str) -> str | None:
    first = text.lstrip().splitlines()[0] if text.strip() else ""
    match = SLASH_RE.match(first.strip())
    return match.group(1) if match else None


def skill_from_path(path: str) -> str | None:
    norm = path.replace("\\", "/")
    if not norm.endswith("SKILL.md"):
        return None
    parts = [part for part in norm.split("/") if part]
    if len(parts) >= 2:
        return parts[-2]
    return None


def hash_duplicates(files: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[str, list[str]] = defaultdict(list)
    for item in files:
        digest = item.get("sha256")
        rel = item.get("path")
        if digest and rel:
            groups[str(digest)].append(str(rel))
    return [
        {"sha256": digest, "paths": paths}
        for digest, paths in groups.items()
        if len(paths) > 1
    ]


def memory_files(paths: list[tuple[str, Path]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    files = []
    for label, path in paths:
        digest = sha256_file(path)
        if digest is None:
            continue
        files.append(
            {
                "path": label,
                "bytes": path.stat().st_size if path.is_file() else 0,
                "sha256": digest,
                "tokens": file_tok(path),
            }
        )
    return files, hash_duplicates(files)


def apply_policy(
    *,
    extensions: list[dict[str, Any]],
    lifetime: dict[str, dict[str, Any]],
    window_hits: dict[str, int],
    sufficient: bool,
    kind: str,
) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for ext in extensions:
        name = str(ext.get("name") or "")
        if not name or not ext.get("enabled"):
            continue
        short = plugin_short(name)
        life = lifetime.get(name) or lifetime.get(short) or {}
        life_count = life.get("usageCount")
        hits = int(window_hits.get(name, 0) + window_hits.get(short, 0))
        if is_passive(name):
            findings.append(
                finding(
                    "1-unused",
                    "INFO",
                    "passive_unknown",
                    f"{name} is passive/no-signal; zero is not a cold verdict",
                    "inventory" if life_count is None else "counter",
                    target=name,
                    extra={"lifetime": life_count, "window": hits},
                )
            )
            continue
        if is_rare_keep(name) and (life_count in (0, None)) and hits == 0:
            findings.append(
                finding(
                    "1-unused",
                    "INFO",
                    "rare_keep",
                    f"{name} is rare maintenance tooling; keep unless you prefer disable",
                    "counter" if life_count is not None else "inventory",
                    target=name,
                    extra={"lifetime": life_count, "window": hits},
                )
            )
            continue
        if not sufficient:
            continue
        if life_count is None:
            if lifetime and kind == "plugin":
                findings.append(
                    finding(
                        "1-unused",
                        "UNKNOWN",
                        "usage_unknown",
                        f"{name} has no lifetime counter; not a cold verdict",
                        "unavailable",
                        target=name,
                        extra={"window": hits},
                    )
                )
            continue
        if life_count == 0 and hits == 0:
            findings.append(
                finding(
                    "1-unused",
                    "WARN",
                    "cold_candidate",
                    f"{name} enabled with zero lifetime and zero window evidence; disable is reversible and attended",
                    "counter" if life_count is not None else "transcript",
                    target=name,
                    extra={"lifetime": life_count, "window": hits},
                )
            )
    return findings


def permission_findings(denials: dict[str, int]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for command, count in sorted(denials.items()):
        if count < 2:
            continue
        kind = permission_class(command)
        if kind == "read":
            findings.append(
                finding(
                    "9-permissions",
                    "INFO",
                    "permission_candidate",
                    f"{command} denied {count}x and looks read-only; allow only in a separate attended step",
                    "transcript",
                    target=command,
                    extra={"count": count, "class": kind},
                )
            )
        else:
            findings.append(
                finding(
                    "9-permissions",
                    "PASS",
                    "permission_write",
                    f"{command} denied {count}x but is write/exec-capable; no allow recommendation",
                    "transcript",
                    target=command,
                    extra={"count": count, "class": kind},
                )
            )
    return findings


def hook_findings(stats: dict[str, dict[str, float]]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for event, row in sorted(stats.items()):
        avg = row.get("avg") or 0.0
        maximum = row.get("max") or 0.0
        count = int(row.get("count") or 0)
        session_start = event.lower().startswith("session")
        limit = SLOW_SESSION_START_MS if session_start else SLOW_PER_TOOL_MS
        if count == 0:
            continue
        if avg > limit or maximum > limit * 2:
            findings.append(
                finding(
                    "5-hooks",
                    "WARN",
                    "slow_hook",
                    f"{event} avg {avg:.0f}ms max {maximum:.0f}ms over {count} samples",
                    "counter",
                    target=event,
                    extra=row,
                )
            )
        else:
            findings.append(
                finding(
                    "5-hooks",
                    "PASS",
                    "hook_ok",
                    f"{event} avg {avg:.0f}ms max {maximum:.0f}ms over {count} samples",
                    "counter",
                    target=event,
                    extra=row,
                )
            )
    return findings


def context_findings(tokens: int | None, label: str) -> list[dict[str, Any]]:
    if tokens is None:
        return [
            finding(
                "6-context",
                "UNKNOWN",
                "context_unknown",
                f"{label} context estimate unavailable",
                "unavailable",
            )
        ]
    if tokens >= CONTEXT_HEAVY_TOKENS:
        return [
            finding(
                "6-context",
                "WARN",
                "context_heavy",
                f"{label} catalog ~{tokens} tok exceeds {CONTEXT_HEAVY_TOKENS}",
                "estimate",
                extra={"tokens": tokens},
            )
        ]
    return [
        finding(
            "6-context",
            "PASS",
            "context_ok",
            f"{label} catalog ~{tokens} tok",
            "estimate",
            extra={"tokens": tokens},
        )
    ]


def duplicate_findings(duplicates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    findings = []
    for item in duplicates:
        paths = item.get("paths") or []
        findings.append(
            finding(
                "2-memory",
                "WARN",
                "duplicate",
                "exact duplicate always-loaded files: " + ", ".join(paths),
                "inventory",
                extra={"paths": paths},
            )
        )
    if not duplicates:
        findings.append(
            finding(
                "2-memory",
                "PASS",
                "memory_ok",
                "no exact-hash duplicates in always-loaded instruction files",
                "inventory",
            )
        )
    findings.append(
        finding(
            "2-memory",
            "INFO",
            "semantic_dup_unsupported",
            "semantic duplication is outside the deterministic script",
            "unavailable",
        )
    )
    return findings


def record_hook(stats: dict[str, dict[str, float]], event: str, duration: float) -> None:
    row = stats.setdefault(event, {"count": 0, "sum": 0.0, "max": 0.0, "avg": 0.0})
    row["count"] += 1
    row["sum"] += duration
    row["max"] = max(row["max"], duration)
    row["avg"] = row["sum"] / row["count"]


# --- TOML-lite (values of secret keys are never kept) ---

def parse_toml_lite(text: str) -> dict[str, Any]:
    tables: dict[str, Any] = {"": {}}
    section = ""
    collecting: str | None = None
    buf: list[str] = []
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        stripped = line.strip()
        if collecting:
            buf.append(stripped)
            if "]" in stripped:
                tables[section][collecting] = "[omitted-array]"
                collecting = None
                buf = []
            continue
        if not stripped:
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1].strip()
            tables.setdefault(section, {})
            continue
        if "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip()
        if is_secret_key(key):
            tables.setdefault(section, {})[key] = "[REDACTED]"
            continue
        if value.startswith("[") and "]" not in value:
            collecting = key
            buf = [value]
            continue
        tables.setdefault(section, {})[key] = _toml_value(value)
    return tables


def _toml_value(value: str) -> Any:
    if value in {"true", "false"}:
        return value == "true"
    if value.startswith("[") and value.endswith("]"):
        return re.findall(r'"([^"]*)"', value)
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return redact_text(value[1:-1])
    return redact_text(value)


def toml_enabled_list(tables: dict[str, Any], section: str, key: str = "enabled") -> list[str]:
    block = tables.get(section) or {}
    value = block.get(key)
    if isinstance(value, list):
        return [str(item) for item in value]
    return []


# --- Claude ---

def claude_transcript_files(home: Path) -> list[Path]:
    root = home / ".claude" / "projects"
    if not root.is_dir():
        return []
    files: list[Path] = []
    for path in root.rglob("*.jsonl"):
        if path.name in SKIP_JSONL_NAMES:
            continue
        files.append(path)
    return files


def parse_claude_transcripts(
    files: list[Path],
) -> tuple[dict[str, int], dict[str, int], dict[str, dict[str, float]], dict[str, int]]:
    skills: dict[str, int] = defaultdict(int)
    tools: dict[str, int] = defaultdict(int)
    hooks: dict[str, dict[str, float]] = {}
    denials: dict[str, int] = defaultdict(int)
    for path in files:
        for obj in iter_jsonl(path):
            kind = obj.get("type")
            if kind == "assistant":
                message = obj.get("message") or {}
                content = message.get("content") if isinstance(message, dict) else None
                if isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict) or block.get("type") != "tool_use":
                            continue
                        name = str(block.get("name") or "")
                        if not name:
                            continue
                        tools[name] += 1
                        if name == "Skill":
                            inp = block.get("input") if isinstance(block.get("input"), dict) else {}
                            skill = str(inp.get("skill") or "")
                            if skill:
                                skills[skill] += 1
            elif kind == "user":
                slash = leading_slash(message_text(obj.get("message")))
                if slash:
                    skills[slash] += 1
                tur = obj.get("toolUseResult")
                if isinstance(tur, dict) and (
                    tur.get("denied") is True or str(tur.get("permissionDecision") or "").lower()
                    in {"deny", "denied", "reject", "rejected"}
                ):
                    command = str(tur.get("command") or tur.get("toolName") or "unknown")
                    denials[command_key(command)] += 1
            elif kind in {"system", "hook"}:
                event = str(obj.get("hookEventName") or obj.get("subtype") or "hook")
                infos = obj.get("hookInfos")
                if isinstance(infos, list):
                    for info in infos:
                        if not isinstance(info, dict):
                            continue
                        duration = info.get("durationMs")
                        hook_event = str(info.get("event") or info.get("hookEventName") or event)
                        if isinstance(duration, (int, float)):
                            record_hook(hooks, hook_event, float(duration))
            elif kind in {"permission-denied", "permission_denied"}:
                command = str(obj.get("command") or obj.get("toolName") or "unknown")
                denials[command_key(command)] += 1
    return dict(skills), dict(tools), hooks, dict(denials)


def claude_plugin_details(name: str) -> int | None:
    if os.environ.get("HARNESS_DOCTOR_SKIP_DETAILS") == "1":
        return None
    path = which("claude")
    if not path:
        return None
    code, out, err = run_cmd([path, "plugin", "details", plugin_short(name)])
    if code != 0:
        return None
    return parse_details_tokens(redact_text(out + "\n" + err))


def audit_claude(home: Path, days: int, limit: int) -> dict[str, Any]:
    claude_json = home / ".claude.json"
    settings_path = home / ".claude" / "settings.json"
    if not claude_json.is_file() and not settings_path.is_file() and not (home / ".claude").exists():
        return empty_harness("claude", "missing", "no ~/.claude or ~/.claude.json")
    data = read_json(claude_json) if claude_json.is_file() else {}
    if data is None:
        data = {}
    if not isinstance(data, dict):
        raise StateError("malformed JSON: ~/.claude.json")
    settings = read_json(settings_path) if settings_path.is_file() else {}
    if settings is None:
        settings = {}
    if settings_path.is_file() and not isinstance(settings, dict):
        raise StateError("malformed JSON: ~/.claude/settings.json")

    result = empty_harness("claude", "present")
    version = cli_version("claude")
    result["version"] = {
        "value": version,
        "status": "PASS" if version else "UNKNOWN",
        "source": "claude --version" if version else "unavailable",
    }
    result["config"] = {
        "installMethod": data.get("installMethod"),
        "numStartups": data.get("numStartups"),
        "firstStartTime": data.get("firstStartTime"),
        "settingsPresent": settings_path.is_file(),
    }
    enabled = []
    raw_enabled = settings.get("enabledPlugins") if isinstance(settings, dict) else {}
    if isinstance(raw_enabled, dict):
        enabled = [name for name, on in raw_enabled.items() if on]
    installed = read_json(home / ".claude" / "plugins" / "installed_plugins.json") or {}
    installed_names = []
    if isinstance(installed, dict):
        plugins = installed.get("plugins") or {}
        if isinstance(plugins, dict):
            installed_names = list(plugins.keys())
    plugins = []
    details_unavailable = which("claude") is None
    for index, name in enumerate(enabled):
        tokens = None
        if not details_unavailable and index < MAX_DETAILS:
            tokens = claude_plugin_details(name)
        plugins.append(
            {
                "name": name,
                "enabled": True,
                "kind": "passive" if is_passive(name) else "active",
                "rare_keep": is_rare_keep(name),
                "est_tokens": tokens,
            }
        )
    result["extensions"]["plugins"] = plugins
    result["extensions"]["mcp"] = sorted(
        (settings.get("enabledMcpjsonServers") or [])
        if isinstance(settings, dict) and isinstance(settings.get("enabledMcpjsonServers"), list)
        else []
    )

    lifetime_plugins = {}
    usage = data.get("pluginUsage") if isinstance(data.get("pluginUsage"), dict) else {}
    for name, row in usage.items():
        if isinstance(row, dict):
            lifetime_plugins[name] = {
                "usageCount": row.get("usageCount"),
                "lastUsedAt": row.get("lastUsedAt"),
                "lastUsedNumStartups": row.get("lastUsedNumStartups"),
            }
    lifetime_skills = {}
    skill_usage = data.get("skillUsage") if isinstance(data.get("skillUsage"), dict) else {}
    for name, row in skill_usage.items():
        if isinstance(row, dict):
            lifetime_skills[name] = {
                "usageCount": row.get("usageCount"),
                "lastUsedAt": row.get("lastUsedAt"),
            }
    result["usage"]["lifetime"] = {"plugins": lifetime_plugins, "skills": lifetime_skills}

    files, window = select_files(claude_transcript_files(home), days, limit)
    skills, tools, hooks, denials = parse_claude_transcripts(files)
    result["usage"]["window"] = {
        **window,
        "skills": skills,
        "tools": {name: count for name, count in tools.items() if name},
        "denials": denials,
    }

    projects = data.get("projects") if isinstance(data.get("projects"), dict) else {}
    for project in projects.values():
        if not isinstance(project, dict):
            continue
        metrics = project.get("lastSessionMetrics")
        if not isinstance(metrics, dict):
            continue
        count = metrics.get("hook_duration_ms_count")
        avg = metrics.get("hook_duration_ms_avg")
        maximum = metrics.get("hook_duration_ms_max")
        if isinstance(count, (int, float)) and count:
            record_hook(hooks, "lastSessionMetrics", float(avg or 0))
            if isinstance(maximum, (int, float)):
                hooks["lastSessionMetrics"]["max"] = max(
                    hooks["lastSessionMetrics"].get("max") or 0.0, float(maximum)
                )
            hooks["lastSessionMetrics"]["count"] = float(count)
    result["hooks"] = hooks

    mem_files, duplicates = memory_files(
        [
            ("claude/CLAUDE.md", home / ".claude" / "CLAUDE.md"),
            *[
                (f"claude/rules/{path.name}", path)
                for path in sorted((home / ".claude" / "rules").glob("*.md"))
            ],
        ]
    )
    result["memory"] = {"files": mem_files, "duplicates": duplicates}

    catalog_root = home / ".claude" / "plugins" / "cache"
    skills_n, catalog_tok = skill_catalog(catalog_root)
    user_n, user_tok = skill_catalog(home / ".claude" / "skills")
    result["context"] = {
        "plugin_catalog_skills": skills_n,
        "plugin_catalog_tokens": catalog_tok,
        "user_skills": user_n,
        "user_skill_tokens": user_tok,
    }
    perms = settings.get("permissions") if isinstance(settings, dict) else {}
    default_mode = perms.get("defaultMode") if isinstance(perms, dict) else None
    result["permissions"] = {"defaultMode": default_mode}

    findings: list[dict[str, Any]] = []
    if data.get("installMethod"):
        findings.append(
            finding(
                "0-setup",
                "INFO",
                "install_method",
                f"installMethod={data.get('installMethod')}; wrappers can disagree with this field",
                "inventory",
            )
        )
    else:
        findings.append(
            finding("0-setup", "UNKNOWN", "install_method", "installMethod missing", "unavailable")
        )
    if version:
        findings.append(
            finding("7-version", "PASS", "version", f"claude {version}", "inventory")
        )
    else:
        findings.append(
            finding("7-version", "UNKNOWN", "version", "claude --version unavailable", "unavailable")
        )
        result["limitations"].append("claude CLI unavailable; version and plugin details unknown")

    findings.extend(
        apply_policy(
            extensions=plugins,
            lifetime=lifetime_plugins,
            window_hits={**skills},
            sufficient=bool(window.get("sufficient")),
            kind="plugin",
        )
    )
    if window.get("sufficient"):
        for name, row in lifetime_skills.items():
            if row.get("usageCount") == 0 and skills.get(name, 0) == 0 and not is_passive(name):
                findings.append(
                    finding(
                        "1-unused",
                        "INFO",
                        "skill_zero",
                        f"skill {name} has lifetime 0 and no window Skill/slash hits; not auto-retired",
                        "counter",
                        target=name,
                    )
                )
    findings.extend(duplicate_findings(duplicates))
    findings.append(
        finding(
            "3-checked-in",
            "INFO",
            "checked_in_skipped",
            "checked-in CLAUDE.md trim is project-scoped and not scanned here",
            "unavailable",
        )
    )
    findings.extend(hook_findings(hooks))
    findings.extend(context_findings(catalog_tok + user_tok, "claude"))
    if default_mode:
        findings.append(
            finding(
                "8-permissions",
                "PASS" if default_mode == "auto" else "INFO",
                "default_mode",
                f"permissions.defaultMode={default_mode}",
                "inventory",
            )
        )
    else:
        findings.append(
            finding(
                "8-permissions",
                "UNKNOWN",
                "default_mode",
                "permissions.defaultMode missing",
                "unavailable",
            )
        )
    findings.extend(permission_findings(denials))
    if details_unavailable:
        result["limitations"].append("claude plugin details unavailable")
    if not window.get("sufficient"):
        result["limitations"].append(
            f"insufficient window ({window.get('session_count')} sessions, "
            f"{window.get('span_days')}d); retirement verdicts withheld"
        )
    result["findings"] = findings
    result["extensions"]["installed"] = installed_names
    return result


# --- Grok ---

def grok_session_dirs(home: Path) -> list[Path]:
    root = home / ".grok" / "sessions"
    if not root.is_dir():
        return []
    found: dict[str, Path] = {}
    for name in ("events.jsonl", "chat_history.jsonl"):
        for path in root.rglob(name):
            found[str(path.parent)] = path.parent
    return list(found.values())


def grok_session_files(home: Path) -> list[Path]:
    files: list[Path] = []
    for folder in grok_session_dirs(home):
        for name in ("events.jsonl", "chat_history.jsonl"):
            path = folder / name
            if path.is_file():
                files.append(path)
                break
    return files


def parse_grok_sessions(
    files: list[Path],
) -> tuple[dict[str, int], dict[str, int], dict[str, int], dict[str, int]]:
    skills: dict[str, int] = defaultdict(int)
    tools: dict[str, int] = defaultdict(int)
    mcp: dict[str, int] = defaultdict(int)
    denials: dict[str, int] = defaultdict(int)
    for path in files:
        folder = path.parent
        events = iter_jsonl(folder / "events.jsonl") if (folder / "events.jsonl").is_file() else []
        history = (
            iter_jsonl(folder / "chat_history.jsonl")
            if (folder / "chat_history.jsonl").is_file()
            else []
        )
        for obj in events:
            kind = obj.get("type")
            if kind in {"tool_started", "tool_completed"}:
                name = str(obj.get("tool_name") or "")
                if name:
                    tools[name] += 1
            elif kind in {"mcp_server_connected", "mcp_server_starting"}:
                name = str(obj.get("server_name") or "")
                if name:
                    mcp[name] += 1
            elif kind == "permission_resolved":
                if str(obj.get("decision") or "").lower() in {"deny", "denied", "reject"}:
                    denials[str(obj.get("tool_name") or "unknown")] += 1
        for obj in history:
            kind = obj.get("type")
            if kind == "user":
                slash = leading_slash(message_text(obj.get("content")))
                if slash:
                    skills[slash] += 1
            elif kind == "assistant":
                for call in obj.get("tool_calls") or []:
                    if not isinstance(call, dict):
                        continue
                    name = str(call.get("name") or "")
                    if name:
                        tools[name] += 1
                    args = call.get("arguments")
                    path_val = ""
                    if isinstance(args, dict):
                        path_val = str(args.get("target_file") or args.get("path") or "")
                    elif isinstance(args, str):
                        try:
                            parsed = json.loads(args)
                        except json.JSONDecodeError:
                            parsed = {}
                        if isinstance(parsed, dict):
                            path_val = str(parsed.get("target_file") or parsed.get("path") or "")
                    skill = skill_from_path(path_val)
                    if skill:
                        skills[skill] += 1
    return dict(skills), dict(tools), dict(mcp), dict(denials)


def grok_inspect() -> dict[str, Any] | None:
    path = which("grok")
    if not path:
        return None
    code, out, _err = run_cmd([path, "inspect", "--json"], timeout=8.0)
    if code != 0 or not out.strip():
        return None
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def learn_status(home: Path) -> dict[str, Any]:
    collector = home / ".grok" / "bundled" / "skills" / "learn" / "collect_sessions.py"
    skill = home / ".grok" / "bundled" / "skills" / "learn" / "SKILL.md"
    present = collector.is_file() or skill.is_file()
    return {
        "collector_present": collector.is_file(),
        "skill_present": skill.is_file(),
        "launched": False,
        "follow_up": "/learn" if present else None,
    }


def audit_grok(home: Path, days: int, limit: int) -> dict[str, Any]:
    grok_home = home / ".grok"
    if not grok_home.exists():
        return empty_harness("grok", "missing", "no ~/.grok")
    result = empty_harness("grok", "present")
    version = cli_version("grok")
    inspect = grok_inspect()
    if inspect and inspect.get("grokVersion"):
        version = str(inspect.get("grokVersion"))
    result["version"] = {
        "value": version,
        "status": "PASS" if version else "UNKNOWN",
        "source": "grok inspect --json" if inspect else ("grok --version" if version else "unavailable"),
    }
    tables = {}
    config_path = grok_home / "config.toml"
    config_text = read_text(config_path)
    if config_text is not None:
        tables = parse_toml_lite(config_text)
    enabled = toml_enabled_list(tables, "plugins")
    inspect_plugins = []
    inspect_skills = []
    inspect_mcp = []
    if inspect:
        for row in inspect.get("plugins") or []:
            if isinstance(row, dict) and row.get("name"):
                inspect_plugins.append(
                    {
                        "name": row.get("name"),
                        "enabled": bool(row.get("enabled", True)),
                        "kind": "passive" if is_passive(str(row.get("name"))) else "active",
                        "rare_keep": is_rare_keep(str(row.get("name"))),
                    }
                )
        for row in inspect.get("skills") or []:
            if isinstance(row, dict) and row.get("name"):
                inspect_skills.append({"name": row.get("name"), "source": (row.get("source") or {}).get("type") if isinstance(row.get("source"), dict) else None})
        for row in inspect.get("mcpServers") or []:
            if isinstance(row, dict) and row.get("name"):
                inspect_mcp.append(str(row.get("name")))
    if not inspect_plugins and enabled:
        inspect_plugins = [
            {
                "name": name,
                "enabled": True,
                "kind": "passive" if is_passive(name) else "active",
                "rare_keep": is_rare_keep(name),
            }
            for name in enabled
        ]
    result["extensions"]["plugins"] = inspect_plugins
    result["extensions"]["skills"] = inspect_skills
    result["extensions"]["mcp"] = inspect_mcp or [
        name[len("mcp_servers.") :].split(".", 1)[0]
        for name in tables
        if name.startswith("mcp_servers.")
    ]
    files, window = select_files(grok_session_files(home), days, limit)
    skills, tools, mcp, denials = parse_grok_sessions(files)
    result["usage"]["window"] = {
        **window,
        "skills": skills,
        "tools": tools,
        "mcp": mcp,
        "denials": denials,
    }
    result["usage"]["lifetime"] = {}
    result["limitations"].append(
        "Grok has no portable lifetime skillUsage counter; window hits are transcript-derived"
    )
    learn = learn_status(home)
    result["config"] = {
        "has_config": config_path.is_file(),
        "learn": learn,
        "inspect": bool(inspect),
    }
    mem_files, duplicates = memory_files(
        [(label, grok_home / rel) for label, rel in GROK_ALWAYS_ON]
    )
    result["memory"] = {"files": mem_files, "duplicates": duplicates}
    skills_n, catalog_tok = skill_catalog(grok_home / "installed-plugins")
    user_n, user_tok = skill_catalog(grok_home / "skills")
    result["context"] = {
        "plugin_catalog_skills": skills_n,
        "plugin_catalog_tokens": catalog_tok,
        "user_skills": user_n,
        "user_skill_tokens": user_tok,
    }
    hooks = inspect.get("hooks") if inspect and isinstance(inspect.get("hooks"), list) else []
    result["hooks"] = {"inventory_count": len(hooks)}
    result["permissions"] = {}
    if inspect and isinstance(inspect.get("permissions"), dict):
        result["permissions"] = {
            "loaded": inspect["permissions"].get("loaded"),
            "managedSettingsActive": inspect["permissions"].get("managedSettingsActive"),
        }

    findings: list[dict[str, Any]] = []
    findings.append(
        finding(
            "0-setup",
            "PASS" if grok_home.is_dir() else "FAIL",
            "setup",
            "grok home present" if grok_home.is_dir() else "grok home missing",
            "inventory",
        )
    )
    if version:
        findings.append(finding("7-version", "PASS", "version", f"grok {version}", "inventory"))
    else:
        findings.append(
            finding("7-version", "UNKNOWN", "version", "grok version unavailable", "unavailable")
        )
        result["limitations"].append("grok CLI inspect/version unavailable")
    window_hits = {**skills, **mcp}
    findings.extend(
        apply_policy(
            extensions=inspect_plugins,
            lifetime={},
            window_hits=window_hits,
            sufficient=bool(window.get("sufficient")),
            kind="plugin",
        )
    )
    if window.get("sufficient"):
        loaded_names = {row["name"] for row in inspect_skills if row.get("name")}
        for name in sorted(loaded_names):
            if skills.get(name, 0) == 0 and not is_passive(name) and not is_rare_keep(name):
                findings.append(
                    finding(
                        "1-unused",
                        "INFO",
                        "skill_window_zero",
                        f"skill {name} has no window load/slash hits; use /learn before retiring",
                        "transcript",
                        target=name,
                    )
                )
    findings.extend(duplicate_findings(duplicates))
    findings.extend(context_findings(catalog_tok + user_tok, "grok"))
    findings.extend(permission_findings(denials))
    if learn["collector_present"] or learn["skill_present"]:
        findings.append(
            finding(
                "1-unused",
                "INFO",
                "learn_follow_up",
                "Grok /learn collector is present; run it separately for qualitative unused-skill review",
                "inventory",
            )
        )
    else:
        findings.append(
            finding(
                "1-unused",
                "UNKNOWN",
                "learn_follow_up",
                "Grok /learn collector not found in this home",
                "unavailable",
            )
        )
    if not window.get("sufficient"):
        result["limitations"].append(
            f"insufficient window ({window.get('session_count')} sessions, "
            f"{window.get('span_days')}d); retirement verdicts withheld"
        )
    result["findings"] = findings
    return result


# --- Codex ---

def codex_rollout_files(home: Path) -> list[Path]:
    root = home / ".codex"
    if not root.exists():
        return []
    files: list[Path] = []
    for path in root.rglob("rollout-*.jsonl"):
        files.append(path)
    return files


def parse_codex_rollouts(files: list[Path]) -> tuple[dict[str, int], str | None]:
    tools: dict[str, int] = defaultdict(int)
    version = None
    for path in files:
        for obj in iter_jsonl(path):
            kind = obj.get("type")
            payload = obj.get("payload") if isinstance(obj.get("payload"), dict) else {}
            if kind == "session_meta" and not version:
                cli = payload.get("cli_version")
                if cli:
                    version = str(cli)
            elif kind == "response_item":
                item_type = payload.get("type")
                if item_type in {"function_call", "custom_tool_call"}:
                    name = str(payload.get("name") or "")
                    if name:
                        tools[name] += 1
    return dict(tools), version


def audit_codex(home: Path, days: int, limit: int) -> dict[str, Any]:
    codex_home = home / ".codex"
    if not codex_home.exists():
        return empty_harness("codex", "missing", "no ~/.codex")
    result = empty_harness("codex", "present")
    version = cli_version("codex")
    tables = {}
    config_path = codex_home / "config.toml"
    text = read_text(config_path)
    if text is not None:
        tables = parse_toml_lite(text)
    files, window = select_files(codex_rollout_files(home), days, limit)
    tools, rollout_version = parse_codex_rollouts(files)
    if rollout_version and not version:
        version = rollout_version
    result["version"] = {
        "value": version,
        "status": "PASS" if version else "UNKNOWN",
        "source": "codex --version" if which("codex") else ("rollout" if version else "unavailable"),
    }
    root_tbl = tables.get("") or {}
    plugins_tbl = tables.get("plugins") or {}
    result["config"] = {
        "has_config": config_path.is_file(),
        "approval_policy": root_tbl.get("approval_policy") or (tables.get("approval") or {}).get("policy"),
        "sandbox_mode": root_tbl.get("sandbox_mode") or (tables.get("sandbox") or {}).get("mode"),
        "plugins_enabled": plugins_tbl.get("enabled"),
        "secret_keys_redacted": sum(
            1
            for block in tables.values()
            if isinstance(block, dict)
            for key in block
            if is_secret_key(str(key))
        ),
    }
    cache = codex_home / "plugins" / "cache"
    plugin_names = []
    if cache.is_dir():
        for child in sorted(cache.iterdir()):
            if child.is_dir() and not child.name.startswith("."):
                plugin_names.append(child.name)
    enabled_flag = plugins_tbl.get("enabled")
    extensions = []
    for name in plugin_names:
        extensions.append(
            {
                "name": name,
                "enabled": True if enabled_flag is not False else False,
                "kind": "passive" if is_passive(name) else "active",
                "rare_keep": is_rare_keep(name),
            }
        )
    result["extensions"]["plugins"] = extensions
    result["usage"]["window"] = {**window, "tools": tools}
    result["usage"]["lifetime"] = {}
    result["limitations"].append(
        "Codex plugin/skill last-use is UNKNOWN; install state is not usage"
    )
    mem_files, duplicates = memory_files(
        [
            ("codex/AGENTS.md", codex_home / "AGENTS.md"),
            ("codex/instructions.md", codex_home / "instructions.md"),
        ]
    )
    result["memory"] = {"files": mem_files, "duplicates": duplicates}
    skills_n, catalog_tok = skill_catalog(cache)
    result["context"] = {"plugin_catalog_skills": skills_n, "plugin_catalog_tokens": catalog_tok}
    result["permissions"] = {
        "approval_policy": result["config"].get("approval_policy"),
        "sandbox_mode": result["config"].get("sandbox_mode"),
    }
    findings = [
        finding("0-setup", "PASS", "setup", "codex home present", "inventory"),
        finding(
            "7-version",
            "PASS" if version else "UNKNOWN",
            "version",
            f"codex {version}" if version else "codex version unavailable",
            "inventory" if version else "unavailable",
        ),
    ]
    findings.extend(
        apply_policy(
            extensions=extensions,
            lifetime={},
            window_hits=tools,
            sufficient=False,
            kind="plugin",
        )
    )
    findings.extend(duplicate_findings(duplicates))
    findings.extend(context_findings(catalog_tok, "codex"))
    if result["permissions"].get("approval_policy"):
        findings.append(
            finding(
                "8-permissions",
                "INFO",
                "approval_policy",
                f"approval_policy={result['permissions']['approval_policy']}",
                "inventory",
            )
        )
    result["findings"] = findings
    if not window.get("sufficient"):
        result["limitations"].append(
            f"insufficient window ({window.get('session_count')} sessions, "
            f"{window.get('span_days')}d); retirement verdicts withheld"
        )
    return result


# --- Cursor ---

def latest_version_dir(root: Path) -> Path | None:
    if not root.is_dir():
        return None
    versions = [path for path in root.iterdir() if path.is_dir() and not path.name.startswith(".")]
    if not versions:
        return None

    def key(path: Path) -> list[Any]:
        parts: list[Any] = []
        for bit in path.name.replace("-", ".").split("."):
            parts.append(int(bit) if bit.isdigit() else bit)
        return parts

    try:
        return sorted(versions, key=key)[-1]
    except Exception:
        return sorted(versions, key=lambda path: path.name)[-1]


def read_plugin_version(root: Path) -> str | None:
    candidates = [
        root / ".claude-plugin" / "plugin.json",
        root / "plugin.json",
        root / ".claude-plugin" / "marketplace.json",
    ]
    for path in candidates:
        data = read_json(path) if path.is_file() else None
        if not isinstance(data, dict):
            continue
        if isinstance(data.get("version"), str) and data["version"]:
            return data["version"]
        meta = data.get("metadata") or {}
        if isinstance(meta, dict) and isinstance(meta.get("version"), str):
            return meta["version"]
        for plugin in data.get("plugins") or []:
            if isinstance(plugin, dict) and plugin.get("name") == "skillwiki" and plugin.get("version"):
                return str(plugin["version"])
    return root.name if root.name else None


def parse_semver(value: str) -> list[Any]:
    return [int(bit) if bit.isdigit() else bit for bit in value.replace("-", ".").split(".")]


def cursor_history_files(home: Path) -> list[Path]:
    files: list[Path] = []
    for path in (
        home / ".cursor" / "prompt_history.jsonl",
        home / ".cursor" / "chats",
    ):
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(path.rglob("*.jsonl"))
    projects = home / ".cursor" / "projects"
    if projects.is_dir():
        files.extend(projects.rglob("*.jsonl"))
    return files


def parse_cursor_history(files: list[Path]) -> dict[str, int]:
    hits: dict[str, int] = defaultdict(int)
    for path in files:
        if path.suffix == ".jsonl":
            rows: list[Any] = iter_jsonl(path)
        else:
            data = read_json(path)
            rows = data if isinstance(data, list) else []
        for obj in rows:
            if not isinstance(obj, dict):
                continue
            command = obj.get("command") or obj.get("slash")
            if isinstance(command, str) and command.startswith("/"):
                name = leading_slash(command)
                if name:
                    hits[name] += 1
                    continue
            text = obj.get("text") if isinstance(obj.get("text"), str) else ""
            name = leading_slash(text)
            if name:
                hits[name] += 1
    return dict(hits)


def audit_cursor(home: Path, days: int, limit: int) -> dict[str, Any]:
    cursor_home = home / ".cursor"
    if not cursor_home.exists():
        return empty_harness("cursor", "missing", "no ~/.cursor")
    result = empty_harness("cursor", "present")
    version = cli_version("cursor-agent") or cli_version("agent")
    result["version"] = {
        "value": version,
        "status": "PASS" if version else "UNKNOWN",
        "source": "cursor-agent --version" if version else "unavailable",
    }
    cli_config_path = cursor_home / "cli-config.json"
    cli_config = read_json(cli_config_path) if cli_config_path.is_file() else {}
    if cli_config_path.is_file() and not isinstance(cli_config, dict):
        raise StateError("malformed JSON: ~/.cursor/cli-config.json")
    if not isinstance(cli_config, dict):
        cli_config = {}
    result["config"] = {
        "has_cli_config": cli_config_path.is_file(),
        "approvalMode": cli_config.get("approvalMode"),
        "sandbox": (cli_config.get("sandbox") or {}).get("mode")
        if isinstance(cli_config.get("sandbox"), dict)
        else None,
    }
    result["permissions"] = {
        "approvalMode": result["config"]["approvalMode"],
        "sandbox": result["config"]["sandbox"],
    }
    settings = read_json(home / ".claude" / "settings.json") or {}
    enabled = []
    if isinstance(settings, dict) and isinstance(settings.get("enabledPlugins"), dict):
        enabled = [name for name, on in settings["enabledPlugins"].items() if on]
    plugins = [
        {
            "name": name,
            "enabled": True,
            "kind": "passive" if is_passive(name) else "active",
            "rare_keep": is_rare_keep(name),
        }
        for name in enabled
    ]
    result["extensions"]["plugins"] = plugins

    claude_sw = latest_version_dir(
        home / ".claude" / "plugins" / "cache" / "llm-wiki" / "skillwiki"
    )
    cursor_pack = latest_version_dir(
        home / ".cursor" / "plugins" / "marketplaces" / "github.com" / "karlorz" / "llm-wiki"
    )
    if cursor_pack is None:
        cursor_pack = latest_version_dir(
            home / ".cursor" / "plugins" / "cache" / "llm-wiki" / "skillwiki"
        )
    claude_ver = read_plugin_version(claude_sw) if claude_sw else None
    cursor_ver = read_plugin_version(cursor_pack) if cursor_pack else None
    stale = False
    if claude_ver and cursor_ver:
        try:
            stale = parse_semver(cursor_ver) < parse_semver(claude_ver)
        except Exception:
            stale = False
    result["extensions"]["cache"] = {
        "claude_skillwiki": claude_ver,
        "cursor_pack": cursor_ver,
        "stale": stale,
    }

    files, window = select_files(cursor_history_files(home), days, limit)
    hits = parse_cursor_history(files)
    result["usage"]["window"] = {**window, "slash": hits}
    result["usage"]["lifetime"] = {}
    result["limitations"].extend(
        [
            "Cursor hook-duration, denial, and skill-dispatch counters are unavailable unless a stable local source exists",
            "prompt history slash hits are not proof an auto-invoked skill fired",
        ]
    )
    skills_n, catalog_tok = skill_catalog(cursor_home / "plugins" / "cache")
    user_n, user_tok = skill_catalog(cursor_home / "skills")
    result["context"] = {
        "plugin_catalog_skills": skills_n,
        "plugin_catalog_tokens": catalog_tok,
        "user_skills": user_n,
        "user_skill_tokens": user_tok,
    }
    mem_files, duplicates = memory_files(
        [
            ("cursor/rules", cursor_home / "rules"),
        ]
        if (cursor_home / "rules").is_file()
        else []
    )
    result["memory"] = {"files": mem_files, "duplicates": duplicates}

    findings = [
        finding("0-setup", "PASS", "setup", "cursor home present", "inventory"),
        finding(
            "7-version",
            "PASS" if version else "UNKNOWN",
            "version",
            f"cursor-agent {version}" if version else "cursor-agent version unavailable",
            "inventory" if version else "unavailable",
        ),
    ]
    if stale:
        findings.append(
            finding(
                "0-setup",
                "WARN",
                "cursor_pack_stale",
                f"Cursor pack {cursor_ver} older than Claude skillwiki {claude_ver}",
                "inventory",
                extra={"claude": claude_ver, "cursor": cursor_ver},
            )
        )
    elif cursor_ver:
        findings.append(
            finding(
                "0-setup",
                "PASS",
                "cursor_pack",
                f"Cursor pack {cursor_ver} matches/newer than Claude {claude_ver}",
                "inventory",
            )
        )
    else:
        findings.append(
            finding(
                "0-setup",
                "INFO",
                "cursor_pack",
                "Cursor marketplace pack absent (optional)",
                "inventory",
            )
        )
    findings.extend(
        apply_policy(
            extensions=plugins,
            lifetime={},
            window_hits=hits,
            sufficient=False,
            kind="plugin",
        )
    )
    findings.extend(duplicate_findings(duplicates))
    findings.extend(context_findings(catalog_tok + user_tok, "cursor"))
    if result["permissions"].get("approvalMode"):
        findings.append(
            finding(
                "8-permissions",
                "INFO",
                "approval_mode",
                f"approvalMode={result['permissions']['approvalMode']}",
                "inventory",
            )
        )
    result["findings"] = findings
    if not window.get("sufficient"):
        result["limitations"].append(
            f"insufficient window ({window.get('session_count')} sessions, "
            f"{window.get('span_days')}d); retirement verdicts withheld"
        )
    return result


# --- report ---

def detect_harnesses(home: Path) -> list[str]:
    found = []
    if (home / ".claude.json").exists() or (home / ".claude").exists():
        found.append("claude")
    if (home / ".grok").exists():
        found.append("grok")
    if (home / ".codex").exists():
        found.append("codex")
    if (home / ".cursor").exists():
        found.append("cursor")
    return found


def render_human(report: dict[str, Any]) -> str:
    lines = [
        f"{SCHEMA}  harness={report.get('requested_harness')}  "
        f"detected={','.join(report.get('detected_harnesses') or [])}",
        "",
    ]
    for name in report.get("requested") or []:
        block = (report.get("harnesses") or {}).get(name) or {}
        avail = block.get("availability")
        version = (block.get("version") or {}).get("value") or "unknown"
        lines.append(f"{name.upper()}  {avail}  {version}")
        counts: dict[str, int] = defaultdict(int)
        for item in block.get("findings") or []:
            counts[str(item.get("severity"))] += 1
        if counts:
            lines.append(
                "  findings: "
                + ", ".join(f"{sev} {counts[sev]}" for sev in SEVERITIES if counts[sev])
            )
        for item in block.get("findings") or []:
            if item.get("severity") in {"WARN", "FAIL", "INFO", "UNKNOWN"}:
                target = item.get("target") or ""
                lines.append(
                    f"  - {item.get('severity')} {item.get('code')} {target} {item.get('summary')}"
                )
        for limitation in block.get("limitations") or []:
            lines.append(f"  limitation: {limitation}")
        lines.append("")
    grok = (report.get("harnesses") or {}).get("grok") or {}
    learn = ((grok.get("config") or {}).get("learn") or {})
    if learn.get("follow_up"):
        lines.append(
            "Follow-up: Grok /learn is available and was not launched."
        )
    lines.append("Read-only. No host configuration was changed.")
    return redact_text("\n".join(lines) + "\n")


def build_report(home: Path, requested: str, days: int, limit: int) -> dict[str, Any]:
    detected = detect_harnesses(home)
    names = list(HARNESSES) if requested == "all" else [requested]
    harnesses: dict[str, Any] = {}
    for name in names:
        if name == "claude":
            harnesses[name] = audit_claude(home, days, limit)
        elif name == "grok":
            harnesses[name] = audit_grok(home, days, limit)
        elif name == "codex":
            harnesses[name] = audit_codex(home, days, limit)
        elif name == "cursor":
            harnesses[name] = audit_cursor(home, days, limit)
    return {
        "schema": SCHEMA,
        "generated_at": utcnow().isoformat(),
        "requested_harness": requested,
        "requested": names,
        "detected_harnesses": detected,
        "window": {"days": days, "limit": limit},
        "harnesses": harnesses,
        "read_only": True,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read-only harness doctor")
    parser.add_argument("--harness", choices=("all",) + HARNESSES, default="all")
    parser.add_argument("--home", type=Path, default=None)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    if args.days <= 0 or args.limit <= 0:
        raise UsageError("--days and --limit must be positive")
    return args


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
    except UsageError as exc:
        sys.stderr.write(f"usage: {exc}\n")
        return 2
    home = args.home if args.home is not None else Path.home()
    home = home.expanduser()
    if not home.exists() or not home.is_dir():
        sys.stderr.write(f"usage: --home is not a directory: {home}\n")
        return 2
    try:
        report = build_report(home, args.harness, args.days, args.limit)
    except StateError as exc:
        sys.stderr.write(f"state: {exc}\n")
        return 1
    if args.json:
        sys.stdout.write(dump_json(report) + "\n")
    else:
        sys.stdout.write(render_human(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
