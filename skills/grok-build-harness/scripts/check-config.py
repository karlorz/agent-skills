#!/usr/bin/env python3
"""Schema-check live ~/.grok/config.toml across three layers:
1. Template-owned keys/tables (assets/config.toml.template)
2. Docs-known tables (26-config-reference.md: live preferred, else vendored config-reference-keys.json)
3. Runtime extras (assets/config-runtime-extras.json, e.g. ["consent"])

Classification:
- privacy and ui.notifications are docs-known
- consent is extra
- Unexpected top-level table: warn by default, fail with --strict
- Malformed extras (e.g. consent version not integer): fail

PII safety:
- Never print consent.account or secret values.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLUGIN_ROOT = HERE.parent
ASSETS = PLUGIN_ROOT / "assets"
TEMPLATE_PATH = ASSETS / "config.toml.template"
VENDORED_KEYS_PATH = ASSETS / "config-reference-keys.json"
EXTRAS_PATH = ASSETS / "config-runtime-extras.json"


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


def get_template_keys(template_file: Path) -> set[str]:
    """Extract top-level keys and tables defined in the template."""
    if not template_file.is_file():
        return set()
    content = template_file.read_text(encoding="utf-8")
    # Clean template placeholders that might not parse if any
    parsed = try_load_toml(content)
    if isinstance(parsed, dict):
        return set(parsed.keys())
    # Fallback to regex if TOML parsing fails due to unreplaced tokens
    keys = set()
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m_table = re.match(r"^\[+([A-Za-z0-9_.-]+)", line)
        if m_table:
            keys.add(m_table.group(1).split(".")[0])
        elif "=" in line:
            k = line.split("=", 1)[0].strip()
            keys.add(k)
    return keys


def get_docs_keys(grok_home: Path, vendored_file: Path) -> set[str]:
    """Get docs-known top-level keys from live user guide or vendored snapshot."""
    live_docs = grok_home / "docs" / "user-guide" / "26-config-reference.md"
    if live_docs.is_file():
        text = live_docs.read_text(encoding="utf-8")
        headings = re.findall(r"^### `([^`]+)`", text, re.MULTILINE)
        return {h.split(".")[0] for h in headings}
    
    if vendored_file.is_file():
        try:
            data = json.loads(vendored_file.read_text(encoding="utf-8"))
            if isinstance(data, list):
                return {item.split(".")[0] for item in data}
            if isinstance(data, dict):
                return {k.split(".")[0] for k in data.keys()}
        except Exception:
            pass
    return set()


def get_runtime_extras(extras_file: Path) -> set[str]:
    """Get runtime extra top-level keys from assets catalog."""
    if extras_file.is_file():
        try:
            data = json.loads(extras_file.read_text(encoding="utf-8"))
            if isinstance(data, list):
                return set(data)
            if isinstance(data, dict):
                return set(data.keys())
        except Exception:
            pass
    return set()


def load_key_sets(grok_home: Path, grokgod: bool = False) -> tuple[set[str], set[str], set[str]]:
    """Return (template_keys, docs_keys, extras_keys)."""
    extras_keys = get_runtime_extras(EXTRAS_PATH)
    if grokgod:
        extras_keys.add("plan_mode")
    return (
        get_template_keys(TEMPLATE_PATH),
        get_docs_keys(grok_home, VENDORED_KEYS_PATH),
        extras_keys,
    )


def validate_consent(consent_table: object) -> list[str]:
    """Validate [consent] structure.
    
    - [consent.answers.aup] and/or [consent.answers.tos]
    - version must be an integer if table exists
    - account is optional string (never print value!)
    - Missing both tables is OK
    """
    errors = []
    if not isinstance(consent_table, dict):
        return ["consent must be a table"]
    
    # Check answers sub-table if present
    answers = consent_table.get("answers")
    if answers is not None:
        if not isinstance(answers, dict):
            return ["consent.answers must be a table"]
        for sub in ("aup", "tos"):
            if sub in answers:
                sub_val = answers[sub]
                if not isinstance(sub_val, dict):
                    errors.append(f"consent.answers.{sub} must be a table")
                    continue
                if "version" in sub_val:
                    if not isinstance(sub_val["version"], int) or isinstance(sub_val["version"], bool):
                        errors.append(f"consent.answers.{sub}.version must be an integer")
                if "account" in sub_val:
                    if not isinstance(sub_val["account"], str):
                        errors.append(f"consent.answers.{sub}.account must be a string")
    return errors


def check_config(config_path: Path, grok_home: Path, strict: bool, grokgod: bool = False) -> int:
    if not config_path.is_file():
        print(f"config file not found: {config_path}", file=sys.stderr)
        return 1

    content = config_path.read_text(encoding="utf-8")
    parsed = try_load_toml(content)
    if parsed is None:
        print(f"ERROR: failed to parse {config_path} as TOML", file=sys.stderr)
        return 1

    template_keys, docs_keys, extras_keys = load_key_sets(grok_home, grokgod)

    errors = []
    warnings = []

    if "consent" in parsed:
        errors.extend(validate_consent(parsed["consent"]))

    for key in parsed.keys():
        if key in template_keys or key in docs_keys or key in extras_keys:
            continue
        msg = f"unexpected top-level table/key: {key}"
        if strict:
            errors.append(msg)
        else:
            warnings.append(msg)

    # Output results
    for msg in warnings:
        print(f"WARNING: {msg}", file=sys.stderr)
    for msg in errors:
        print(f"ERROR: {msg}", file=sys.stderr)

    if errors:
        return 1
    return 0


def classify_inspect_path(path: str, template_keys: set[str], docs_keys: set[str], extras_keys: set[str]) -> str:
    """Classify an inspect configWarnings path (e.g. ui.notifications) by its root table."""
    root = (path or "").split(".", 1)[0]
    if root in extras_keys:
        return "extra"
    if root in docs_keys:
        return "docs-lag"
    if root in template_keys:
        return "template-owned"
    return "unexpected"


def classify_inspect_warnings(inspect_data: object, grok_home: Path, grokgod: bool = False) -> list[str]:
    """Return classified inspect warning lines. Never includes secret values."""
    if not isinstance(inspect_data, dict):
        return []
    template_keys, docs_keys, extras_keys = load_key_sets(grok_home, grokgod)
    lines = []
    warnings = inspect_data.get("configWarnings") or []
    for warning in warnings:
        if not isinstance(warning, dict):
            continue
        path = str(warning.get("path") or "")
        kind = str(warning.get("kind") or "unknown")
        label = classify_inspect_path(path, template_keys, docs_keys, extras_keys)
        lines.append(f"{kind} {path}: {label}")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(description="Schema-check config.toml")
    parser.add_argument("--config", type=Path, help="Path to config.toml")
    parser.add_argument("--grok-home", type=Path, help="Path to GROK_HOME")
    parser.add_argument("--strict", action="store_true", help="Fail on unexpected keys")
    parser.add_argument("--grokgod", action="store_true", help="Allow grokgod-specific runtime keys (e.g. plan_mode)")
    parser.add_argument(
        "--classify-inspect",
        nargs="?",
        const="-",
        metavar="FILE",
        help="Classify grok inspect --json configWarnings from FILE or stdin (-)",
    )
    args = parser.parse_args()

    grok_home = args.grok_home or Path(os.environ.get("GROK_HOME", Path.home() / ".grok"))
    config_path = args.config or (grok_home / "config.toml")

    if args.classify_inspect is not None:
        if args.classify_inspect == "-":
            raw = sys.stdin.read()
        else:
            raw = Path(args.classify_inspect).read_text(encoding="utf-8")
        try:
            inspect_data = json.loads(raw)
        except Exception:
            print("ERROR: failed to parse inspect JSON", file=sys.stderr)
            sys.exit(1)
        for line in classify_inspect_warnings(inspect_data, grok_home, args.grokgod):
            print(line)
        sys.exit(0)

    exit_code = check_config(config_path, grok_home, args.strict, args.grokgod)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
