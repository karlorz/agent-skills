#!/usr/bin/env python3
"""Parse and validate fenced dev-loop YAML configuration documents."""

from __future__ import annotations

import base64
import copy
import datetime as datetime_module
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except Exception:  # PyYAML is an optional runtime capability for this bridge.
    yaml = None


PARSER_NAME = "pyyaml"


def schema(kind: str, **options: Any) -> dict[str, Any]:
    return {"kind": kind, **options}


STRING = schema("string")
NULLABLE_STRING = schema("string", nullable=True)
BOOLEAN = schema("boolean")
INTEGER = schema("integer")
JSON_VALUE = schema("any")
STRING_LIST = schema("list", item=STRING)


def mapping(
    fields: dict[str, dict[str, Any]],
    *,
    additional: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return schema("map", fields=fields, additional=additional)


def list_of(item: dict[str, Any]) -> dict[str, Any]:
    return schema("list", item=item)


STRING_MAP = mapping({}, additional=NULLABLE_STRING)

PRD_BACKEND = mapping(
    {
        "capabilities": STRING_LIST,
        "skills": STRING_MAP,
    }
)

DISCIPLINE = mapping(
    {
        "skill": STRING,
        "when": STRING,
        "mode": STRING,
        "include_paths": STRING_LIST,
        "exclude_paths": STRING_LIST,
    }
)

CRITICAL_PATH = mapping(
    {
        "code": STRING_LIST,
        "vault": STRING_LIST,
        "history_pins": STRING_LIST,
    }
)

KNOWLEDGE_BACKEND = mapping(
    {
        "vault": NULLABLE_STRING,
        "cli_entry": NULLABLE_STRING,
        "work_dir": NULLABLE_STRING,
        "capabilities": STRING_LIST,
        "skills": STRING_MAP,
    }
)

TOP_LEVEL_SCHEMA = mapping(
    {
        "slug": STRING,
        "release_branch": STRING,
        "branch_policy": mapping(
            {
                "default_work_branch": STRING,
                "direct_push_to_release_branch": BOOLEAN,
                "pr_fallback": STRING,
                "branch_protection_required": BOOLEAN,
                "feature_branch_pattern": NULLABLE_STRING,
                "require_feature_branch": BOOLEAN,
                "release_branch": NULLABLE_STRING,
            }
        ),
        "worktree_policy": mapping(
            {
                "required": BOOLEAN,
                "release_branch": NULLABLE_STRING,
                "feature_branch_pattern": NULLABLE_STRING,
                "allow_detached": BOOLEAN,
                "allow_submodules": BOOLEAN,
                "sandbox_root": NULLABLE_STRING,
                "enforce_before_write": BOOLEAN,
            }
        ),
        "task_sandbox": mapping(
            {
                "required": BOOLEAN,
                "owner": NULLABLE_STRING,
                "root": NULLABLE_STRING,
                "allow_shared": BOOLEAN,
                "isolation": NULLABLE_STRING,
                "ownership_file": NULLABLE_STRING,
            }
        ),
        "verification": mapping(
            {
                "commands": list_of(JSON_VALUE),
                "scripts": list_of(JSON_VALUE),
                "timeout_seconds": INTEGER,
                "required": BOOLEAN,
                "allow_failure": BOOLEAN,
            }
        ),
        "dispatch": mapping(
            {
                "platforms": JSON_VALUE,
                "spawn": JSON_VALUE,
                "wait": JSON_VALUE,
                "cleanup": JSON_VALUE,
                "model": NULLABLE_STRING,
                "isolation": NULLABLE_STRING,
                "capabilities": STRING_LIST,
                "fallback": JSON_VALUE,
            }
        ),
        "prd_layer": STRING,
        "prd_pipeline": STRING,
        "prd_backends": mapping({}, additional=PRD_BACKEND),
        "prd_disciplines": list_of(DISCIPLINE),
        "critical_paths": mapping({}, additional=CRITICAL_PATH),
        "fact_check": mapping(
            {
                "enabled": BOOLEAN,
                "source_order": STRING_LIST,
                "web_tools": mapping(
                    {
                        "primary": NULLABLE_STRING,
                        "deep_fetch": NULLABLE_STRING,
                        "site_map": NULLABLE_STRING,
                        "plan_first": NULLABLE_STRING,
                    }
                ),
                "triggers": STRING_LIST,
                "evidence_contract": mapping(
                    {
                        "require_sources_used_section": BOOLEAN,
                        "cite_session_id": BOOLEAN,
                    }
                ),
            }
        ),
        "idle_deep_research": mapping(
            {
                "enabled": BOOLEAN,
                "skill": STRING,
                "trigger": mapping(
                    {
                        "when": STRING,
                        "if": STRING,
                        "cooldown": STRING,
                        "max_per_day": INTEGER,
                    }
                ),
                "topic_seeds": STRING_LIST,
                "topic_selection": mapping(
                    {
                        "bias_toward": STRING,
                        "skip_if_recent_query_page_exists": schema(
                            "string_or_integer"
                        ),
                    }
                ),
                "output_mode": STRING,
                "budget": mapping(
                    {
                        "web_searches": INTEGER,
                        "deep_fetches": INTEGER,
                        "context7_calls": INTEGER,
                    }
                ),
                "followups": mapping(
                    {
                        "on_finding": STRING,
                        "p_score_default": STRING,
                    }
                ),
                # These fields are emitted by the current setup workflow and
                # predate the template's nested trigger/topic-selection form.
                "bias_toward": STRING,
                "cooldown_cycles": INTEGER,
                "max_per_day": INTEGER,
                "skip_if_recent_query_page_exists": schema(
                    "string_or_integer"
                ),
            }
        ),
        "investigate": mapping(
            {
                "max_items": INTEGER,
                "topic_seeds": STRING_LIST,
            }
        ),
        "preflight": mapping(
            {
                "enabled": BOOLEAN,
                "default_limit": INTEGER,
                "default_lanes": STRING_LIST,
                "require_approved_spec_and_plan": BOOLEAN,
                "unattended_not_ready_behavior": STRING,
                "defaults": mapping({}, additional=JSON_VALUE),
            }
        ),
        "browser_verification": mapping(
            {
                "enabled": BOOLEAN,
                "trigger": STRING_LIST,
                "prerequisites": STRING_LIST,
                "driver": NULLABLE_STRING,
                "base_url": NULLABLE_STRING,
                "smoke_routes": STRING_LIST,
                "reviser_workflow": STRING_LIST,
                "e2e_fallback": NULLABLE_STRING,
            }
        ),
        "reactive_debugging": mapping(
            {
                "enabled": BOOLEAN,
                "auto_retry_attempts": INTEGER,
                "evidence_dir": NULLABLE_STRING,
                "evidence_capture": STRING_LIST,
                "fact_check_tool": NULLABLE_STRING,
                "escalate_after": mapping(
                    {
                        "consecutive_idle_cycles": INTEGER,
                        "same_error_signature": BOOLEAN,
                    }
                ),
                "escalation_action": STRING,
            }
        ),
        "code_review": mapping(
            {
                "parallel": BOOLEAN,
                "codex": mapping(
                    {
                        "enabled_in_normal": BOOLEAN,
                        "enabled_in_high": BOOLEAN,
                        "agent": STRING,
                    }
                ),
            }
        ),
        "knowledge_layer": STRING,
        "knowledge_backends": mapping({}, additional=KNOWLEDGE_BACKEND),
        "vault": NULLABLE_STRING,
        "vault_auto_commit": BOOLEAN,
        "vault_sync": mapping(
            {
                "peer_aware": BOOLEAN,
                "lock_timeout_seconds": INTEGER,
                "retry_budget": INTEGER,
                "presync_skill": STRING,
                "fallback": STRING,
            }
        ),
        "interview": mapping(
            {
                "setup": mapping(
                    {
                        "skill": STRING,
                        "glossary": NULLABLE_STRING,
                    }
                ),
                "work_item": mapping(
                    {
                        # Live configs document an explicit native default plus
                        # optional external upgrade install metadata.
                        "default": NULLABLE_STRING,
                        "upgrade": NULLABLE_STRING,
                        "source": NULLABLE_STRING,
                        "install": NULLABLE_STRING,
                        "trigger": STRING,
                        "goal_override": STRING,
                    }
                ),
            }
        ),
        "cli_src": NULLABLE_STRING,
        "cli_test": NULLABLE_STRING,
        "skills_glob": NULLABLE_STRING,
        "cli_entry_override": NULLABLE_STRING,
        "e2e_scripts": STRING_LIST,
        "bump_script": NULLABLE_STRING,
        "publish_via": NULLABLE_STRING,
        "deploy_script": NULLABLE_STRING,
        "release_script": NULLABLE_STRING,
        "manifests_count": INTEGER,
        "remote_hosts": STRING_LIST,
        "release_policy": mapping(
            {
                "auto_bump": BOOLEAN,
                "channel": STRING,
                "trigger_globs": STRING_LIST,
                "skip_globs": STRING_LIST,
                "tag_format": STRING,
                "verify_after_push": BOOLEAN,
                "stable_release_guard": NULLABLE_STRING,
            }
        ),
        "ci_configured": BOOLEAN,
        "ci_workflow": NULLABLE_STRING,
        "release_workflow": NULLABLE_STRING,
        "ci_discovery": STRING,
        "required_checks": STRING_LIST,
        "branch_protection": BOOLEAN,
        "merge_policy": mapping(
            {
                "strategy": STRING,
                "auto_merge": BOOLEAN,
                "merge_method": STRING,
                "require_work_item_approval": BOOLEAN,
            }
        ),
        "notes": mapping({}, additional=JSON_VALUE),
        # The template shows these preflight metadata keys in fenced examples.
        # Keeping their shapes known preserves template-derived vocabulary.
        "automation_ready": BOOLEAN,
        "human_questions_resolved": BOOLEAN,
        "spec_preflight_approved": BOOLEAN,
        "plan_preflight_approved": BOOLEAN,
        "preflight_state": STRING,
        "last_preflight": STRING,
        "merge_auto_approved": BOOLEAN,
    }
)


OPEN_FENCE_RE = re.compile(r"^(?P<indent> {0,3})(?P<fence>`{3,}|~{3,})(?P<info>.*)$")
YAML_KEY_RE = re.compile(
    r"^(?P<indent>[ ]*)(?P<key>[a-z_][a-z0-9_-]*):(?P<value>[ \t].*|[ \t]*)$"
)
YAML_LIST_MAPPING_RE = re.compile(
    r"^(?P<indent>[ ]*)-[ \t]+(?P<key>[a-z_][a-z0-9_-]*):(?P<value>[ \t].*|[ \t]*)$"
)
YAML_LIST_ITEM_RE = re.compile(r"^(?P<indent>[ ]*)-[ \t]+(?P<value>\S.*)$")


def base_result(available: bool, version: str | None) -> dict[str, Any]:
    return {
        "config": {},
        "provenance": {},
        "blocks": [],
        "errors": [],
        "warnings": [],
        "parser": {
            "name": PARSER_NAME,
            "available": available,
            "version": version,
        },
    }


def diagnostic(
    code: str,
    message: str,
    *,
    path: str | None = None,
    line: int | None = None,
    block_index: int | None = None,
) -> dict[str, Any]:
    return {
        "code": code,
        "message": message,
        "path": path,
        "line": line,
        "block_index": block_index,
    }


def diagnostic_sort_key(item: dict[str, Any]) -> tuple[Any, ...]:
    return (
        item.get("path") or "",
        item.get("line") if item.get("line") is not None else -1,
        item.get("code") or "",
        item.get("block_index")
        if item.get("block_index") is not None
        else -1,
        item.get("message") or "",
    )


def parse_arguments(argv: list[str]) -> tuple[str | None, list[dict[str, Any]]]:
    file_path = None
    errors: list[dict[str, Any]] = []
    index = 0
    while index < len(argv):
        argument = argv[index]
        if argument == "--file":
            if index + 1 >= len(argv) or argv[index + 1].startswith("--"):
                errors.append(
                    diagnostic(
                        "invalid_arguments",
                        "--file requires a Markdown file path",
                    )
                )
            else:
                index += 1
                file_path = argv[index]
        else:
            errors.append(
                diagnostic(
                    "invalid_arguments",
                    f"unknown argument: {argument}",
                )
            )
        index += 1

    if file_path is None and not errors:
        errors.append(
            diagnostic(
                "invalid_arguments",
                "--file requires a Markdown file path",
            )
        )
    return file_path, errors


def is_closing_fence(line: str, marker: str) -> bool:
    match = re.match(r"^ {0,3}(?P<fence>`+|~+)[ \t]*$", line)
    if match is None:
        return False
    candidate = match.group("fence")
    return candidate[0] == marker[0] and len(candidate) >= len(marker)


def extract_yaml_blocks(
    text: str,
) -> tuple[list[dict[str, Any]], set[int], list[dict[str, Any]]]:
    lines = text.splitlines()
    blocks: list[dict[str, Any]] = []
    fenced_lines: set[int] = set()
    errors: list[dict[str, Any]] = []
    active: dict[str, Any] | None = None

    for offset, line in enumerate(lines):
        line_number = offset + 1
        if active is not None:
            fenced_lines.add(line_number)
            if not is_closing_fence(line, active["marker"]):
                continue

            if active["language"] in {"yaml", "yml"}:
                content_lines = lines[active["offset"] + 1 : offset]
                content = "\n".join(content_lines)
                if content_lines:
                    content += "\n"
                block_index = len(blocks)
                blocks.append(
                    {
                        "index": block_index,
                        "language": active["language"],
                        "fence_start_line": active["offset"] + 1,
                        "content_start_line": active["offset"] + 2,
                        "content_end_line": offset,
                        "fence_end_line": line_number,
                        "content": content,
                    }
                )
            active = None
            continue

        match = OPEN_FENCE_RE.match(line)
        if match is None:
            continue
        marker = match.group("fence")
        info = match.group("info").strip()
        language = info.split(None, 1)[0].lower() if info else ""
        active = {
            "marker": marker,
            "language": language,
            "offset": offset,
        }
        fenced_lines.add(line_number)

    if active is not None and active["language"] in {"yaml", "yml"}:
        content_lines = lines[active["offset"] + 1 :]
        content = "\n".join(content_lines)
        if content_lines:
            content += "\n"
        block_index = len(blocks)
        blocks.append(
            {
                "index": block_index,
                "language": active["language"],
                "fence_start_line": active["offset"] + 1,
                "content_start_line": active["offset"] + 2,
                "content_end_line": len(lines),
                "fence_end_line": None,
                "content": content,
            }
        )
        errors.append(
            diagnostic(
                "unterminated_yaml_fence",
                "YAML code fence is not terminated",
                line=active["offset"] + 1,
                block_index=block_index,
            )
        )

    return blocks, fenced_lines, errors


def join_path(parent: str, key: str) -> str:
    return f"{parent}.{key}" if parent else key


def collect_provenance(
    node: Any,
    *,
    path: str,
    block_index: int,
    content_start_line: int,
    provenance: dict[str, dict[str, int]],
    errors: list[dict[str, Any]],
) -> None:
    if isinstance(node, yaml.nodes.MappingNode):
        seen: set[str] = set()
        for key_node, value_node in node.value:
            if isinstance(key_node, yaml.nodes.ScalarNode):
                key = key_node.value
            else:
                key = "<complex-key>"
            child_path = join_path(path, key)
            source_line = content_start_line + key_node.start_mark.line
            if key in seen:
                errors.append(
                    diagnostic(
                        "duplicate_key",
                        f"duplicate YAML key: {child_path}",
                        path=child_path,
                        line=source_line,
                        block_index=block_index,
                    )
                )
            seen.add(key)
            provenance[child_path] = {
                "block_index": block_index,
                "line": source_line,
            }
            collect_provenance(
                value_node,
                path=child_path,
                block_index=block_index,
                content_start_line=content_start_line,
                provenance=provenance,
                errors=errors,
            )
        return

    if isinstance(node, yaml.nodes.SequenceNode):
        for index, child_node in enumerate(node.value):
            child_path = f"{path}[{index}]" if path else f"[{index}]"
            provenance[child_path] = {
                "block_index": block_index,
                "line": content_start_line + child_node.start_mark.line,
            }
            collect_provenance(
                child_node,
                path=child_path,
                block_index=block_index,
                content_start_line=content_start_line,
                provenance=provenance,
                errors=errors,
            )


def yaml_error_line(error: Exception, content_start_line: int) -> int:
    mark = getattr(error, "problem_mark", None) or getattr(
        error, "context_mark", None
    )
    if mark is None:
        return content_start_line
    return content_start_line + mark.line


def yaml_error_message(error: Exception) -> str:
    problem = getattr(error, "problem", None)
    if isinstance(problem, str) and problem:
        return problem
    return str(error).splitlines()[0] if str(error) else type(error).__name__


def actual_type(value: Any) -> str:
    if value is None:
        return "null"
    if type(value) is bool:
        return "boolean"
    if type(value) is int:
        return "integer"
    if type(value) is float:
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "list"
    if isinstance(value, dict):
        return "map"
    return type(value).__name__


def expected_type(schema_node: dict[str, Any]) -> str:
    kind = schema_node["kind"]
    if schema_node.get("nullable"):
        return f"{kind} or null"
    if kind == "string_or_integer":
        return "string or integer"
    return kind


def value_matches_schema(value: Any, schema_node: dict[str, Any]) -> bool:
    if value is None:
        return bool(schema_node.get("nullable"))
    kind = schema_node["kind"]
    if kind == "any":
        return True
    if kind == "string":
        return isinstance(value, str)
    if kind == "boolean":
        return type(value) is bool
    if kind == "integer":
        return type(value) is int
    if kind == "string_or_integer":
        return isinstance(value, str) or type(value) is int
    if kind == "list":
        return isinstance(value, list)
    if kind == "map":
        return isinstance(value, dict)
    return False


def source_line_for_path(
    path: str,
    provenance: dict[str, dict[str, int]],
    fallback: int,
) -> int:
    source = provenance.get(path)
    if source is not None:
        return source["line"]
    return fallback


def validate_value(
    value: Any,
    schema_node: dict[str, Any],
    *,
    path: str,
    block_index: int,
    provenance: dict[str, dict[str, int]],
    fallback_line: int,
    errors: list[dict[str, Any]],
) -> None:
    if not value_matches_schema(value, schema_node):
        display_path = path or None
        errors.append(
            diagnostic(
                "invalid_type",
                (
                    f"{path or 'configuration root'} must be "
                    f"{expected_type(schema_node)}, got {actual_type(value)}"
                ),
                path=display_path,
                line=source_line_for_path(path, provenance, fallback_line),
                block_index=block_index,
            )
        )
        return

    if value is None or schema_node["kind"] == "any":
        return

    if schema_node["kind"] == "list":
        item_schema = schema_node["item"]
        for index, item in enumerate(value):
            item_path = f"{path}[{index}]" if path else f"[{index}]"
            validate_value(
                item,
                item_schema,
                path=item_path,
                block_index=block_index,
                provenance=provenance,
                fallback_line=fallback_line,
                errors=errors,
            )
        return

    if schema_node["kind"] != "map":
        return

    fields = schema_node["fields"]
    additional = schema_node.get("additional")
    for key, child in value.items():
        if not isinstance(key, str):
            source_path = join_path(path, str(key))
            errors.append(
                diagnostic(
                    "invalid_key_type",
                    f"mapping keys must be strings, got {actual_type(key)}",
                    path=source_path,
                    line=source_line_for_path(
                        source_path, provenance, fallback_line
                    ),
                    block_index=block_index,
                )
            )
            continue

        child_path = join_path(path, key)
        child_schema = fields.get(key, additional)
        if child_schema is None:
            errors.append(
                diagnostic(
                    "unknown_key",
                    f"unknown configuration key: {child_path}",
                    path=child_path,
                    line=source_line_for_path(
                        child_path, provenance, fallback_line
                    ),
                    block_index=block_index,
                )
            )
            continue

        validate_value(
            child,
            child_schema,
            path=child_path,
            block_index=block_index,
            provenance=provenance,
            fallback_line=fallback_line,
            errors=errors,
        )


def stable_key(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True, ensure_ascii=True)
    except (TypeError, ValueError):
        return repr(value)


def json_safe(value: Any, active: set[int] | None = None) -> Any:
    if active is None:
        active = set()

    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else str(value)
    if isinstance(value, (datetime_module.date, datetime_module.datetime)):
        return value.isoformat()
    if isinstance(value, bytes):
        return base64.b64encode(value).decode("ascii")

    value_id = id(value)
    if value_id in active:
        raise ValueError("recursive YAML aliases are not supported")

    if isinstance(value, dict):
        active.add(value_id)
        normalized: dict[str, Any] = {}
        for key, child in value.items():
            normalized_key = key if isinstance(key, str) else str(key)
            normalized[normalized_key] = json_safe(child, active)
        active.remove(value_id)
        return normalized

    if isinstance(value, (list, tuple)):
        active.add(value_id)
        normalized_list = [json_safe(child, active) for child in value]
        active.remove(value_id)
        return normalized_list

    if isinstance(value, set):
        active.add(value_id)
        normalized_set = [json_safe(child, active) for child in value]
        active.remove(value_id)
        return sorted(normalized_set, key=stable_key)

    return str(value)


def provenance_is_within(candidate: str, path: str) -> bool:
    return (
        candidate == path
        or candidate.startswith(f"{path}.")
        or candidate.startswith(f"{path}[")
    )


def replace_provenance_subtree(
    target: dict[str, dict[str, int]],
    incoming: dict[str, dict[str, int]],
    path: str,
) -> None:
    for candidate in list(target):
        if provenance_is_within(candidate, path):
            del target[candidate]
    for candidate, source in incoming.items():
        if provenance_is_within(candidate, path):
            target[candidate] = copy.deepcopy(source)


def deep_merge(
    target: dict[str, Any],
    incoming: dict[str, Any],
    *,
    path: str,
    provenance: dict[str, dict[str, int]],
    incoming_provenance: dict[str, dict[str, int]],
) -> None:
    for key, incoming_value in incoming.items():
        child_path = join_path(path, key)
        if (
            key in target
            and isinstance(target[key], dict)
            and isinstance(incoming_value, dict)
        ):
            if child_path in incoming_provenance:
                provenance[child_path] = copy.deepcopy(
                    incoming_provenance[child_path]
                )
            deep_merge(
                target[key],
                incoming_value,
                path=child_path,
                provenance=provenance,
                incoming_provenance=incoming_provenance,
            )
            continue

        target[key] = copy.deepcopy(incoming_value)
        replace_provenance_subtree(
            provenance,
            incoming_provenance,
            child_path,
        )


def scan_unfenced_yaml(
    text: str,
    fenced_lines: set[int],
) -> list[dict[str, Any]]:
    errors: list[dict[str, Any]] = []
    stack: list[tuple[int, str]] = []
    list_indexes: dict[str, int] = {}
    known_top_level = set(TOP_LEVEL_SCHEMA["fields"])

    for line_number, line in enumerate(text.splitlines(), start=1):
        if line_number in fenced_lines:
            continue

        key_match = YAML_KEY_RE.match(line)
        list_mapping_match = YAML_LIST_MAPPING_RE.match(line)
        list_item_match = YAML_LIST_ITEM_RE.match(line)

        if key_match is not None:
            indent = len(key_match.group("indent"))
            key = key_match.group("key")
            while stack and stack[-1][0] >= indent:
                stack.pop()
            parent_path = stack[-1][1] if stack else ""

            looks_like_config = bool(parent_path) or key in known_top_level
            if not looks_like_config:
                looks_like_config = "_" in key or "-" in key
            if not looks_like_config:
                stack.clear()
                continue

            path = join_path(parent_path, key)
            errors.append(
                diagnostic(
                    "unfenced_yaml",
                    f"YAML-like configuration must be inside a fenced block: {path}",
                    path=path,
                    line=line_number,
                )
            )
            value = key_match.group("value").strip()
            if not value or value.startswith("#"):
                stack.append((indent, path))
            continue

        if list_mapping_match is not None:
            indent = len(list_mapping_match.group("indent"))
            while stack and stack[-1][0] >= indent:
                stack.pop()
            parent_path = stack[-1][1] if stack else ""
            key = list_mapping_match.group("key")
            if not parent_path and key not in known_top_level and "_" not in key:
                continue
            index = list_indexes.get(parent_path, 0)
            list_indexes[parent_path] = index + 1
            prefix = f"{parent_path}[{index}]" if parent_path else f"[{index}]"
            path = join_path(prefix, key)
            errors.append(
                diagnostic(
                    "unfenced_yaml",
                    f"YAML-like configuration must be inside a fenced block: {path}",
                    path=path,
                    line=line_number,
                )
            )
            value = list_mapping_match.group("value").strip()
            if not value or value.startswith("#"):
                stack.append((indent, path))
            continue

        if list_item_match is not None and stack:
            indent = len(list_item_match.group("indent"))
            while stack and stack[-1][0] >= indent:
                stack.pop()
            if not stack:
                continue
            parent_path = stack[-1][1]
            index = list_indexes.get(parent_path, 0)
            list_indexes[parent_path] = index + 1
            path = f"{parent_path}[{index}]"
            errors.append(
                diagnostic(
                    "unfenced_yaml",
                    f"YAML-like configuration must be inside a fenced block: {path}",
                    path=path,
                    line=line_number,
                )
            )
            continue

        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            stack.clear()

    return errors


def public_block(block: dict[str, Any]) -> dict[str, Any]:
    return {
        "index": block["index"],
        "language": block["language"],
        "fence_start_line": block["fence_start_line"],
        "content_start_line": block["content_start_line"],
        "content_end_line": block["content_end_line"],
        "fence_end_line": block["fence_end_line"],
    }


def parse_document(text: str, result: dict[str, Any]) -> None:
    blocks, fenced_lines, fence_errors = extract_yaml_blocks(text)
    result["blocks"] = [public_block(block) for block in blocks]
    result["errors"].extend(fence_errors)
    result["errors"].extend(scan_unfenced_yaml(text, fenced_lines))

    for block in blocks:
        if block["fence_end_line"] is None:
            continue

        try:
            node = yaml.compose(block["content"], Loader=yaml.SafeLoader)
            loaded = yaml.safe_load(block["content"])
        except yaml.YAMLError as error:
            result["errors"].append(
                diagnostic(
                    "malformed_yaml",
                    yaml_error_message(error),
                    line=yaml_error_line(error, block["content_start_line"]),
                    block_index=block["index"],
                )
            )
            continue

        if node is None and loaded is None:
            loaded = {}

        block_provenance: dict[str, dict[str, int]] = {}
        if node is not None:
            collect_provenance(
                node,
                path="",
                block_index=block["index"],
                content_start_line=block["content_start_line"],
                provenance=block_provenance,
                errors=result["errors"],
            )

        validate_value(
            loaded,
            TOP_LEVEL_SCHEMA,
            path="",
            block_index=block["index"],
            provenance=block_provenance,
            fallback_line=block["content_start_line"],
            errors=result["errors"],
        )

        if not isinstance(loaded, dict):
            continue

        try:
            normalized = json_safe(loaded)
        except ValueError as error:
            result["errors"].append(
                diagnostic(
                    "unsupported_yaml_value",
                    str(error),
                    line=block["content_start_line"],
                    block_index=block["index"],
                )
            )
            continue

        deep_merge(
            result["config"],
            normalized,
            path="",
            provenance=result["provenance"],
            incoming_provenance=block_provenance,
        )

    result["errors"].sort(key=diagnostic_sort_key)
    result["warnings"].sort(key=diagnostic_sort_key)


def write_result(result: dict[str, Any]) -> None:
    sys.stdout.write(
        json.dumps(
            result,
            indent=2,
            sort_keys=True,
            ensure_ascii=True,
            allow_nan=False,
        )
    )
    sys.stdout.write("\n")


def main(argv: list[str]) -> int:
    file_path, argument_errors = parse_arguments(argv)
    parser_available = yaml is not None
    parser_version = (
        str(getattr(yaml, "__version__", "unknown"))
        if parser_available
        else None
    )
    result = base_result(parser_available, parser_version)

    if not parser_available:
        result["errors"].append(
            diagnostic(
                "parser_unavailable",
                "PyYAML is unavailable; dev-loop configuration cannot be parsed safely",
            )
        )
        result["errors"].extend(argument_errors)
        result["errors"].sort(key=diagnostic_sort_key)
        write_result(result)
        return 1

    if argument_errors:
        result["errors"].extend(argument_errors)
        result["errors"].sort(key=diagnostic_sort_key)
        write_result(result)
        return 1

    try:
        if file_path == "-":
            text = sys.stdin.read()
        else:
            text = Path(file_path).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        result["errors"].append(
            diagnostic(
                "file_read_error",
                f"cannot read configuration file: {error}",
            )
        )
        write_result(result)
        return 1

    try:
        parse_document(text, result)
    except Exception as error:  # Preserve the JSON bridge contract on failure.
        result["config"] = {}
        result["provenance"] = {}
        result["errors"].append(
            diagnostic(
                "internal_parser_error",
                f"configuration parser failed: {type(error).__name__}: {error}",
            )
        )
        result["errors"].sort(key=diagnostic_sort_key)

    write_result(result)
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
