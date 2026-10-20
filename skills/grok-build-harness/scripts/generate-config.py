#!/usr/bin/env python3
"""Render the sanitized config.toml.template into a live ~/.grok/config.toml.

Token substitution:
  __HUB_API_KEY__        hub.karldigi.dev gateway key (5 models)
  __NEW_API_KEY__        new.karldigi.dev gateway key (gpt-5.6-sol, gpt-5.6-luna, flash-*)
  __CONTEXT7_API_KEY__   context7 MCP key
  __ENABLED_PLUGINS__    comma-separated plugin names for [plugins].enabled

Empty api_key tokens drop the whole `api_key = "..."` line so env_key keeps
working (grok-build resolves api_key > env_key; an absent field is cleanest).

Preservation (ADR-3, 2026-08-09): with --preserve <existing>, host state the
template does not own is carried over:
  * skills.{ignore,disabled,paths,server_skill_dirs,bundled_skill_dirs} and
    plugins.paths become a stable, duplicate-free union of template defaults
    and host entries (template entries first);
  * the requested [plugins].enabled list and every other value the template
    emits stay template-owned;
  * keys absent from the template inside shared tables, whole extra tables,
    extra [[marketplace.sources]], and top-level scalars retain their values.

Unsupported host shapes (type changes, mixed arrays, nested values inside an
array of tables) abort before the destination is written.

The rendered config must parse with tomllib/tomli. A missing parser or a
malformed host config is a hard error: preservation never falls back to text
guessing. Installing the staged result into the live config is
scripts/install-config.py.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_TEMPLATE = HERE.parent / "assets" / "config.toml.template"

API_KEY_TOKENS = ("__HUB_API_KEY__", "__NEW_API_KEY__", "__CONTEXT7_API_KEY__")
TOKEN_RE = re.compile(r"__[A-Z][A-Z0-9_]*__")

# Tables whose array values are a union of template defaults and host entries.
MERGED_ARRAY_KEYS: dict[str, tuple[str, ...]] = {
    "skills": ("ignore", "disabled", "paths", "server_skill_dirs", "bundled_skill_dirs"),
    "plugins": ("paths",),
}

_MISSING = object()


class ParserUnavailable(RuntimeError):
    """No tomllib/tomli in this interpreter."""


class InvalidConfig(ValueError):
    """Host or rendered config cannot be preserved safely."""


def _toml_module():
    try:
        import tomllib  # Python 3.11+
    except ModuleNotFoundError:
        try:
            import tomli  # pip install tomli on older Pythons
        except ModuleNotFoundError as exc:
            raise ParserUnavailable(
                "no TOML parser available (need Python 3.11+ tomllib or tomli)"
            ) from exc
        return tomli
    return tomllib


def load_toml(text: str, source: object) -> dict:
    """Parse TOML or raise ParserUnavailable / InvalidConfig."""
    module = _toml_module()
    try:
        parsed = module.loads(text)
    except Exception as exc:
        raise InvalidConfig(f"{source}: malformed TOML ({exc})") from exc
    if not isinstance(parsed, dict):
        raise InvalidConfig(f"{source}: TOML root is not a table")
    return parsed


def read_text(path: Path) -> str:
    """Read UTF-8 text and drop a leading BOM (Windows editors add one)."""
    text = path.read_text(encoding="utf-8")
    return text[1:] if text.startswith("\ufeff") else text


def toml_scalar(value) -> str:
    """Serialize a scalar (or list of scalars) as a TOML value."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat()
    if isinstance(value, list):
        if any(isinstance(item, dict) for item in value):
            raise InvalidConfig(
                "array-of-tables values are not supported for preservation"
            )
        return "[" + ", ".join(toml_scalar(item) for item in value) + "]"
    raise InvalidConfig(f"unsupported preserved value type: {type(value).__name__}")


def toml_key(key: str) -> str:
    """Quote a TOML key only when it needs quoting."""
    if re.fullmatch(r"[A-Za-z0-9_-]+", key):
        return key
    return json.dumps(key, ensure_ascii=False)


def _kind(value) -> str:
    if isinstance(value, dict):
        return "table"
    if isinstance(value, list):
        return "array"
    return "scalar"


def _string_array(value, dotted: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise InvalidConfig(
            f"{dotted}: unsupported preservation shape (expected an array of strings, "
            f"got {_kind(value)})"
        )
    return list(value)


def merge_string_arrays(template_values, host_values, dotted: str) -> list[str]:
    """Stable, duplicate-free union: template order first, then host additions."""
    merged: list[str] = []
    seen: set[str] = set()
    for item in _string_array(template_values, dotted) + _string_array(host_values, dotted):
        if item not in seen:
            seen.add(item)
            merged.append(item)
    return merged


@dataclasses.dataclass
class Preserved:
    """Host state to splice back into the rendered template."""

    preamble: list[str] = dataclasses.field(default_factory=list)
    arrays: dict[str, list[tuple[str, list[str]]]] = dataclasses.field(default_factory=dict)
    keys: dict[str, list[tuple[str, object]]] = dataclasses.field(default_factory=dict)
    # (root table, block) pairs; ordered against the template's table order so
    # repeated merges of the same config stay byte-identical
    tail: list[tuple[str, str]] = dataclasses.field(default_factory=list)

    def add_table(self, dotted: str, fields: list[str]) -> None:
        root = dotted.split(".", 1)[0].strip('"')
        self.tail.append((root, "\n".join([f"[{dotted}]", *fields])))

    def add_array_table(self, dotted: str, fields: list[str]) -> None:
        root = dotted.split(".", 1)[0].strip('"')
        self.tail.append((root, "\n".join([f"[[{dotted}]]", *fields])))

    def empty(self) -> bool:
        return not (self.preamble or self.arrays or self.keys or self.tail)


def collect_extras(existing: dict, rendered: dict, template_keys: dict[str, set[str]]) -> Preserved:
    """Find host state the render must keep, validating shapes as it goes.

    `template_keys` maps a table path to the keys the template declares there,
    including keys this run legitimately dropped (an empty api_key token). A
    key the template declares is template-owned even when it is absent from the
    render, so an env-only render cannot be re-keyed from host leftovers.
    """
    out = Preserved()

    def walk(host_node: dict, tpl_node: dict, path: str) -> None:
        for key, value in host_node.items():
            dotted = f"{path}.{toml_key(key)}" if path else toml_key(key)
            if path == "marketplace" and key == "sources" and isinstance(value, list):
                _preserve_marketplace_sources(value, tpl_node.get("sources"), dotted, out)
                continue
            tpl_value = tpl_node.get(key, _MISSING)
            if tpl_value is _MISSING:
                if key in template_keys.get(path, set()):
                    continue
                _preserve_absent(value, dotted, path, key, out)
                continue
            host_kind, tpl_kind = _kind(value), _kind(tpl_value)
            if host_kind == "table" and tpl_kind == "table":
                walk(value, tpl_value, dotted)
                continue
            if host_kind != tpl_kind:
                raise InvalidConfig(
                    f"{dotted}: unsupported preservation shape "
                    f"(host {host_kind}, template {tpl_kind})"
                )
            if key in MERGED_ARRAY_KEYS.get(path, ()):
                merged = merge_string_arrays(tpl_value, value, dotted)
                if merged != tpl_value:
                    out.arrays.setdefault(path, []).append((key, merged))
            # every other emitted key stays template-owned

    walk(existing, rendered, "")
    return out


def _preserve_marketplace_sources(host_sources, tpl_sources, dotted: str, out: Preserved) -> None:
    render_names = {
        entry.get("name") for entry in tpl_sources if isinstance(entry, dict)
    } if isinstance(tpl_sources, list) else set()
    for entry in host_sources:
        if not isinstance(entry, dict):
            raise InvalidConfig(f"{dotted}: unsupported preservation shape (entry is not a table)")
        if entry.get("name") in render_names:
            continue
        out.add_array_table(dotted, _array_table_fields(entry, dotted, "a marketplace source"))


def _array_table_fields(entry: dict, dotted: str, context: str) -> list[str]:
    fields = []
    for key, value in entry.items():
        if isinstance(value, (dict, list)):
            raise InvalidConfig(
                f"{dotted}.{toml_key(key)}: unsupported preservation shape "
                f"(nested table or array inside {context})"
            )
        fields.append(f"{toml_key(key)} = {toml_scalar(value)}")
    return fields


def _table_blocks(prefix: str, table: dict) -> list[tuple[str, list[str]]]:
    """Flatten a host table into (dotted path, scalar field lines) blocks."""
    scalars = [
        f"{toml_key(key)} = {toml_scalar(value)}"
        for key, value in table.items()
        if not isinstance(value, dict)
    ]
    blocks = [(prefix, scalars)] if scalars or not table else []
    for key, value in table.items():
        if isinstance(value, dict):
            blocks.extend(_table_blocks(f"{prefix}.{toml_key(key)}", value))
    return blocks


def _preserve_absent(value, dotted: str, path: str, key: str, out: Preserved) -> None:
    """Preserve a host key the template does not emit."""
    if isinstance(value, dict):
        for block_path, fields in _table_blocks(dotted, value):
            out.add_table(block_path, fields)
        return
    if isinstance(value, list) and any(isinstance(item, dict) for item in value):
        for entry in value:
            if not isinstance(entry, dict):
                raise InvalidConfig(f"{dotted}: unsupported preservation shape (mixed array)")
            out.add_array_table(
                dotted, _array_table_fields(entry, dotted, "an array of tables")
            )
        return
    if path == "":
        # top-level scalars must precede every table header
        out.preamble.append(f"{dotted} = {toml_scalar(value)}")
        return
    out.keys.setdefault(path, []).append((key, value))


def template_key_map(template: dict) -> dict[str, set[str]]:
    """Map table path -> the keys the template declares there."""
    out: dict[str, set[str]] = {}

    def walk(node: dict, path: str) -> None:
        out[path] = set(node)
        for key, value in node.items():
            if isinstance(value, dict):
                walk(value, f"{path}.{toml_key(key)}" if path else toml_key(key))

    walk(template, "")
    return out


def preserved_extras(existing_path: str, rendered: str, template: dict) -> Preserved:
    """Compute host state to preserve from an existing config."""
    source = Path(existing_path)
    if not source.is_file():
        return Preserved()
    existing = load_toml(read_text(source), source)
    rendered_parsed = load_toml(rendered, "rendered config")
    return collect_extras(existing, rendered_parsed, template_key_map(template))


def _array_lines(key: str, values: list) -> list[str]:
    single = f"{toml_key(key)} = [" + ", ".join(toml_scalar(item) for item in values) + "]"
    if len(single) <= 100:
        return [single]
    return [f"{toml_key(key)} = ["] + [
        f"    {toml_scalar(item)}," for item in values
    ] + ["]"]


def _value_lines(key: str, value) -> list[str]:
    if isinstance(value, list) and not any(isinstance(item, dict) for item in value):
        return _array_lines(key, value)
    return [f"{toml_key(key)} = {toml_scalar(value)}"]


def _section_start(lines: list[str], path: str) -> int | None:
    header = f"[{path}]"
    for i, line in enumerate(lines):
        if line.strip() == header:
            return i
    return None


def _value_span(lines: list[str], section_start: int, key: str) -> tuple[int, int] | None:
    """Return the line span of `key = ...` inside a section, arrays included."""
    pattern = re.compile(
        rf'^\s*(?:{re.escape(toml_key(key))}|"{re.escape(key)}")\s*='
    )
    for i in range(section_start + 1, len(lines)):
        if lines[i].lstrip().startswith("["):
            return None
        match = pattern.match(lines[i])
        if not match:
            continue
        depth = 0
        quote = ""
        seen_open = False
        for j in range(i, len(lines)):
            chunk = lines[j][match.end():] if j == i else lines[j]
            k = 0
            while k < len(chunk):
                ch = chunk[k]
                if quote:
                    if ch == "\\" and quote == '"':
                        k += 2
                        continue
                    if ch == quote:
                        quote = ""
                elif ch in "\"'":
                    quote = ch
                elif ch == "[":
                    depth += 1
                    seen_open = True
                elif ch == "]":
                    depth -= 1
                k += 1
            if seen_open and depth <= 0:
                return (i, j)
        return None
    return None


def _root_order(lines: list[str]) -> dict[str, int]:
    """Map each top-level table name to its first header position."""
    order: dict[str, int] = {}
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("["):
            continue
        name = stripped[2:] if stripped.startswith("[[") else stripped[1:]
        root = name.split(".", 1)[0].split("]", 1)[0].strip().strip('"')
        order.setdefault(root, i)
    return order


def _ordered_tail(tail: list[tuple[str, str]], rendered_lines: list[str]) -> list[str]:
    """Order preserved blocks by the rendered config's table order.

    Blocks for tables the template knows follow the template; blocks for
    host-only tables go last in host order. Without this, a second merge of the
    previous output would reorder blocks and break byte idempotency.
    """
    order = _root_order(rendered_lines)
    fallback = len(rendered_lines)
    indexed = [
        (order.get(root, fallback), position, block)
        for position, (root, block) in enumerate(tail)
    ]
    return [block for _, _, block in sorted(indexed)]


def assemble(rendered: str, preserved: Preserved) -> str:
    """Splice preserved host state into the rendered text at valid positions."""
    if preserved.empty():
        return rendered
    lines = rendered.splitlines()

    for path in sorted(preserved.arrays):
        start = _section_start(lines, path)
        if start is None:
            raise InvalidConfig(f"[{path}]: rendered config has no such table")
        for key, values in preserved.arrays[path]:
            span = _value_span(lines, start, key)
            if span is None:
                raise InvalidConfig(
                    f"[{path}].{key}: rendered config does not emit this array"
                )
            lines[span[0]:span[1] + 1] = _array_lines(key, values)

    for path, entries in preserved.keys.items():
        start = _section_start(lines, path)
        inserted: list[str] = []
        for key, value in entries:
            inserted.extend(_value_lines(key, value))
        if start is None:
            # the template only declares this table implicitly through
            # sub-tables ([model."x"]), so opening it at the end is valid TOML
            lines = lines + [""] + [f"[{path}]"] + inserted
            continue
        lines[start + 1:start + 1] = inserted

    if preserved.preamble:
        first_table = next(
            (i for i, line in enumerate(lines) if line.lstrip().startswith("[")), None
        )
        if first_table is None:
            lines = preserved.preamble + lines
        else:
            lines = lines[:first_table] + preserved.preamble + lines[first_table:]

    if preserved.tail:
        lines = lines + [""] + _ordered_tail(preserved.tail, rendered.splitlines())

    return "\n".join(lines) + "\n"


def render(template: str, values: dict[str, str], enabled: list[str]) -> str:
    lines = template.splitlines()
    out: list[str] = []

    for line in lines:
        stripped = line.strip()
        matched = False
        for token in API_KEY_TOKENS:
            if stripped == f'api_key = "{token}"':
                value = values.get(token, "").strip()
                if value:
                    out.append(f'api_key = "{value}"')
                # empty -> drop the line entirely (env_key fallback)
                matched = True
                break
        if matched:
            continue
        if stripped == 'enabled = ["__ENABLED_PLUGINS__"]':
            quoted = ", ".join(f'"{name}"' for name in enabled)
            out.append(f"enabled = [{quoted}]")
            continue
        out.append(line)

    rendered = "\n".join(out) + "\n"

    # the context7 key lives in the MCP args array, not an api_key line
    ctx7 = values.get("__CONTEXT7_API_KEY__", "").strip()
    if ctx7:
        rendered = rendered.replace('"__CONTEXT7_API_KEY__"', f'"{ctx7}"')
    else:
        # drop the "--api-key" argument pair so the MCP stays launchable
        rendered = re.sub(
            r'[ \t]*"--api-key",\n[ \t]*"__CONTEXT7_API_KEY__",\n', "", rendered
        )

    # permission_mode is a plain token in the [ui] section
    rendered = rendered.replace(
        '"__PERMISSION_MODE__"', f'"{values.get("__PERMISSION_MODE__", "always-approve")}"'
    )

    # tokens may still appear in comment lines documenting the template;
    # only non-comment lines must be free of them
    code_lines = [line for line in rendered.splitlines() if not line.strip().startswith("#")]
    leftovers = sorted(set(TOKEN_RE.findall("\n".join(code_lines))))
    if leftovers:
        raise SystemExit(
            f"generate-config: unresolved tokens after rendering: {leftovers}"
        )
    return rendered


def build(args: argparse.Namespace) -> str:
    template = read_text(args.template)
    enabled = [name.strip() for name in args.enabled.split(",") if name.strip()]

    values = {
        "__HUB_API_KEY__": args.hub_key,
        "__NEW_API_KEY__": args.new_key,
        "__CONTEXT7_API_KEY__": args.context7_key,
        "__PERMISSION_MODE__": args.permission_mode,
    }

    # require a parser up front: preservation and the final schema assertions
    # are meaningless without a real parse, so never write a guessed config
    template_parsed = load_toml(template, args.template)

    rendered = render(template, values, enabled)
    if args.preserve:
        rendered = assemble(
            rendered, preserved_extras(args.preserve, rendered, template_parsed)
        )

    parsed = load_toml(rendered, "rendered config")
    models = parsed.get("model", {})
    missing = [name for name in ("sonnet", "haiku", "deepseek-v4-flash") if name not in models]
    if missing:
        raise InvalidConfig(f"rendered config missing model aliases: {missing}")
    enabled_out = parsed.get("plugins", {}).get("enabled", [])
    if args.enabled and set(enabled) != set(enabled_out):
        raise InvalidConfig(
            f"enabled mismatch: wanted {sorted(enabled)}, got {sorted(enabled_out)}"
        )
    permission = parsed.get("ui", {}).get("permission_mode")
    if permission != args.permission_mode:
        raise InvalidConfig(
            f"permission_mode mismatch: wanted {args.permission_mode!r}, got {permission!r}"
        )
    return rendered


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--out", type=Path, required=True,
                        help="destination path for the rendered config.toml")
    parser.add_argument("--hub-key", default="",
                        help="hub.karldigi.dev API key (or leave empty for env_key-only)")
    parser.add_argument("--new-key", default="",
                        help="new.karldigi.dev API key (or leave empty for env_key-only)")
    parser.add_argument("--context7-key", default="",
                        help="context7 MCP API key (required for the MCP server)")
    parser.add_argument("--permission-mode", default="always-approve",
                        choices=("always-approve", "plan"),
                        help="permission_mode for [ui] (default: always-approve; use 'plan' for shared hosts)")
    parser.add_argument("--enabled", default="",
                        help="comma-separated plugin names for [plugins].enabled")
    parser.add_argument("--preserve", "--preserve-sources", default="",
                        dest="preserve",
                        help="existing config.toml whose host-owned keys (skill/plugin "
                             "path arrays, [plugins].disabled, extra tables) are merged "
                             "into the rendered output")
    args = parser.parse_args(argv)

    try:
        rendered = build(args)
    except ParserUnavailable as exc:
        print(
            f"generate-config: ERROR: {exc}; refusing to write {args.out}",
            file=sys.stderr,
        )
        return 2
    except InvalidConfig as exc:
        print(f"generate-config: ERROR: {exc}; {args.out} left unchanged", file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered, encoding="utf-8")
    print(f"generate-config: wrote {args.out} ({len(rendered.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
