#!/usr/bin/env python3
"""Render the sanitized config.toml.template into a live ~/.grok/config.toml.

Token substitution:
  __HUB_API_KEY__        hub.karldigi.dev gateway key (5 models)
  __NEW_API_KEY__        new.karldigi.dev gateway key (gpt-5.6-luna, glm-5.2)
  __CONTEXT7_API_KEY__   context7 MCP key
  __ENABLED_PLUGINS__    comma-separated plugin names for [plugins].enabled

Empty api_key tokens drop the whole `api_key = "..."` line so env_key keeps
working (grok-build resolves api_key > env_key; an absent field is cleanest).
The rendered config is validated with tomllib/tomli before writing.
"""

import argparse
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
    return tomllib.loads(text)


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
