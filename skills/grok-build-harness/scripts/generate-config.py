#!/usr/bin/env python3
"""Render the sanitized config.toml.template into a live ~/.grok/config.toml.

Token substitution:
  __HUB_API_KEY__        hub.karldigi.dev gateway key (5 models)
  __NEW_API_KEY__        new.karldigi.dev gateway key (gpt-5.6-luna, glm-5.2)
  __CONTEXT7_API_KEY__   context7 MCP key
  __ENABLED_PLUGINS__    comma-separated plugin names for [plugins].enabled

Empty api_key tokens drop the whole `api_key = "..."` line so env_key keeps
working (grok-build resolves api_key > env_key; an absent field is cleanest).

Preservation (ADR-3, 2026-08-09): with --preserve <existing>, any key the
template does not emit is carried over from the existing config — host-set
state like [plugins].disabled, extra marketplace sources, or whole extra
tables (e.g. a user-added [model."custom"]) survives re-runs. Template-owned
keys keep winning by design.

The rendered config is validated with tomllib/tomli before writing.
"""

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_TEMPLATE = HERE.parent / "assets" / "config.toml.template"

API_KEY_TOKENS = ("__HUB_API_KEY__", "__NEW_API_KEY__", "__CONTEXT7_API_KEY__")
TOKEN_RE = re.compile(r"__[A-Z][A-Z0-9_]*__")


def try_load_toml(text: str) -> object:
    """Return the parsed TOML, or None when no parser is available."""
    try:
        import tomllib  # Python 3.11+
    except ModuleNotFoundError:
        try:
            import tomli as tomllib  # pip install tomli on older Pythons
        except ModuleNotFoundError:
            return None
    try:
        return tomllib.loads(text)
    except Exception:
        return None


def toml_scalar(value) -> str:
    """Serialize a scalar (or list of scalars) as a TOML value."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        if any(isinstance(item, dict) for item in value):
            raise ValueError(
                "array-of-tables values are not supported for preservation"
            )
        return "[" + ", ".join(toml_scalar(item) for item in value) + "]"
    raise ValueError(f"unsupported preserved value type: {type(value).__name__}")


def toml_key(key: str) -> str:
    """Quote a TOML key only when it needs quoting."""
    if re.fullmatch(r"[A-Za-z0-9_-]+", key):
        return key
    return json.dumps(key, ensure_ascii=False)


def table_lines(prefix: str, table: dict) -> list[str]:
    """Emit a table block: `[prefix]` header, scalar keys, nested sub-tables."""
    scalars = []
    nested = []
    for key, value in table.items():
        if isinstance(value, dict):
            nested.append((key, value))
        else:
            scalars.append(f"{toml_key(key)} = {toml_scalar(value)}")
    out = []
    if scalars:
        out.append(f"[{prefix}]")
        out.extend(scalars)
    for key, value in nested:
        out.extend(table_lines(f"{prefix}.{toml_key(key)}", value))
    return out


def collect_extras(existing: dict, rendered: dict) -> tuple:
    """Recursively find keys present in `existing` but absent in `rendered`.

    Returns (preamble, plugins_keys, tail):
      preamble     list of top-level scalar lines (must precede any table)
      plugins_keys list of (key, value) pairs for [plugins] sub-keys, which
                   must be injected inside the emitted [plugins] section
      tail         list of block strings appended at the end (new tables and
                   [[marketplace.sources]] entries)
    """
    preamble: list[str] = []
    plugins_keys: list[tuple] = []
    tail: list[str] = []

    def walk(existing_node: dict, rendered_node: dict, path: str) -> None:
        rendered_node = rendered_node or {}
        for key, value in existing_node.items():
            dotted = f"{path}.{toml_key(key)}" if path else toml_key(key)
            rendered_value = rendered_node.get(key)
            # marketplace.sources is an array of tables: keep entries whose
            # name the rendered config does not declare (grok CLI and users
            # can add sources to a live config)
            if (
                key == "sources"
                and path == "marketplace"
                and isinstance(value, list)
            ):
                rendered_names = {
                    s.get("name")
                    for s in rendered_value
                    if isinstance(s, dict)
                } if isinstance(rendered_value, list) else set()
                for entry in value:
                    if (
                        isinstance(entry, dict)
                        and entry.get("name") not in rendered_names
                    ):
                        fields = "\n".join(
                            f"{toml_key(k)} = {toml_scalar(v)}"
                            for k, v in entry.items()
                            if not isinstance(v, (dict, list))
                        )
                        tail.append(f"[[{dotted}]]\n{fields}")
                continue
            if rendered_value is not None:
                # template owns every key it emits (values included); only
                # recurse into shared tables to find their extra sub-keys
                if isinstance(value, dict) and isinstance(rendered_value, dict):
                    walk(value, rendered_value, dotted)
                continue
            # key missing from the render -> host-set state, preserve it
            if path == "plugins" and not isinstance(value, dict):
                plugins_keys.append((key, value))  # injected into [plugins]
                continue
            if isinstance(value, dict):
                tail.extend(table_lines(dotted, value))
            elif isinstance(value, list) and any(
                isinstance(item, dict) for item in value
            ):
                for entry in value:
                    if isinstance(entry, dict):
                        fields = "\n".join(
                            f"{toml_key(k)} = {toml_scalar(v)}"
                            for k, v in entry.items()
                            if not isinstance(v, (dict, list))
                        )
                        tail.append(f"[[{dotted}]]\n{fields}")
            elif path == "":
                # top-level scalars must precede every table header
                preamble.append(f"{dotted} = {toml_scalar(value)}")
            # scalar sub-keys of emitted tables are template-owned; not
            # preserved (documented limitation of the whitelist)

    walk(existing, rendered, "")
    return preamble, plugins_keys, tail


def preserved_extras(existing_path: str, rendered: str) -> tuple:
    """Compute the preserve blocks for an existing config vs the render.

    Falls back to text-level marketplace-source preservation when no TOML
    parser is available.
    """
    existing = Path(existing_path)
    if not existing.is_file():
        return [], [], []
    parsed = try_load_toml(existing.read_text(encoding="utf-8"))
    rendered_parsed = try_load_toml(rendered)
    if parsed is None or rendered_parsed is None:
        # no parser: keep the original source-preservation behavior
        return _sources_only_fallback(existing_path, rendered)
    return collect_extras(parsed, rendered_parsed)


def _sources_only_fallback(existing_path: str, rendered: str) -> tuple:
    """Text-level preservation of [[marketplace.sources]] (no TOML parser)."""
    existing = Path(existing_path)
    text = existing.read_text(encoding="utf-8")
    rendered_names = set(re.findall(r'name = "([^"]+)"', rendered))
    tail = []
    in_sources = False
    current = []
    for line in text.splitlines():
        if line.startswith("[[marketplace.sources]]"):
            in_sources = True
            current = []
            continue
        if in_sources:
            if line.startswith("[[") or line.startswith("["):
                in_sources = False
            elif line.startswith("name = "):
                name = re.match(r'name = "([^"]+)"', line).group(1)
                if name not in rendered_names:
                    current.append(line)
                else:
                    current = []
                    in_sources = False
            elif current:
                current.append(line)
            if not in_sources and current:
                tail.append("[[marketplace.sources]]\n" + "\n".join(current))
    if in_sources and current:
        tail.append("[[marketplace.sources]]\n" + "\n".join(current))
    return [], [], tail


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


def assemble(rendered: str, extras: tuple) -> str:
    """Splice preserved extras into the rendered text at valid positions."""
    preamble, plugins_keys, tail = extras
    if not preamble and not plugins_keys and not tail:
        return rendered
    lines = rendered.splitlines()
    if plugins_keys:
        # [plugins] sub-keys must live inside the emitted [plugins] section:
        # inject right after the enabled line (duplicate headers and dotted
        # keys after a header are both invalid TOML)
        injected = False
        for i, line in enumerate(lines):
            if line.strip().startswith("enabled = ["):
                lines[i + 1 : i + 1] = [
                    f"{toml_key(k)} = {toml_scalar(v)}" for k, v in plugins_keys
                ]
                injected = True
                break
        if not injected:
            lines = lines + ["[plugins]"] + [
                f"{toml_key(k)} = {toml_scalar(v)}" for k, v in plugins_keys
            ]
    if preamble:
        first_table = next(
            (i for i, line in enumerate(lines) if line.startswith("[")), None
        )
        if first_table is None:
            lines = preamble + lines
        else:
            lines = lines[:first_table] + preamble + lines[first_table:]
    if tail:
        lines = lines + [""] + tail
    return "\n".join(lines) + "\n"


def main() -> int:
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
                        help="existing config.toml whose host-set keys (marketplace "
                             "sources, [plugins].disabled, extra tables) are merged "
                             "into the rendered output")
    args = parser.parse_args()

    template = args.template.read_text(encoding="utf-8")
    enabled = [name.strip() for name in args.enabled.split(",") if name.strip()]

    values = {
        "__HUB_API_KEY__": args.hub_key,
        "__NEW_API_KEY__": args.new_key,
        "__CONTEXT7_API_KEY__": args.context7_key,
        "__PERMISSION_MODE__": args.permission_mode,
    }

    rendered = render(template, values, enabled)
    if args.preserve:
        rendered = assemble(rendered, preserved_extras(args.preserve, rendered))

    parsed = try_load_toml(rendered)
    if parsed is None:
        print("generate-config: warning: no tomllib/tomli available; TOML not parsed", file=sys.stderr)
    else:
        models = parsed.get("model", {})
        missing = [name for name in ("sonnet", "haiku", "deepseek-v4-flash") if name not in models]
        if missing:
            raise SystemExit(f"generate-config: rendered config missing model aliases: {missing}")
        enabled_out = parsed.get("plugins", {}).get("enabled", [])
        if args.enabled and set(enabled) != set(enabled_out):
            raise SystemExit(
                f"generate-config: enabled mismatch: wanted {sorted(enabled)}, got {sorted(enabled_out)}"
            )
        permission = parsed.get("ui", {}).get("permission_mode")
        if permission != args.permission_mode:
            raise SystemExit(
                f"generate-config: permission_mode mismatch: wanted {args.permission_mode!r}, got {permission!r}"
            )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered, encoding="utf-8")
    print(f"generate-config: wrote {args.out} ({len(rendered.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
