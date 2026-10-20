#!/usr/bin/env python3
"""Static context-budget inventory tests. Fixtures under /tmp, no live CLI."""

from __future__ import annotations

import importlib.util
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUDGET = ROOT / "skills" / "grok-build-harness" / "scripts" / "context_budget.py"

PASS = 0
FAIL = 0


def ok(label: str) -> None:
    global PASS
    PASS += 1
    print(f"PASS: {label}")


def fail(label: str, detail: str) -> None:
    global FAIL
    FAIL += 1
    print(f"FAIL: {label} — {detail}")


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        ok(label)
    else:
        fail(label, detail)


def load_mod():
    spec = importlib.util.spec_from_file_location("context_budget_under_test", BUDGET)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write(path: Path, text: str, *, newline: str = "\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = text.replace("\n", newline).encode("utf-8")
    path.write_bytes(data)


def write_skill(root: Path, rel: str, frontmatter: str, body: str = "body\n") -> None:
    write(root / rel / "SKILL.md", f"---\n{frontmatter}\n---\n{body}")


def frontmatter_cases() -> list[tuple[str, str, tuple[str, str]]]:
    return [
        (
            "same-line plain",
            "---\nname: alpha\ndescription: plain value\n---\nbody\n",
            ("alpha", "plain value"),
        ),
        (
            "same-line double quoted",
            '---\nname: "beta"\ndescription: "quoted: value"\n---\nbody\n',
            ("beta", "quoted: value"),
        ),
        (
            "same-line single quoted",
            "---\nname: 'gamma'\ndescription: 'single quoted'\n---\nbody\n",
            ("gamma", "single quoted"),
        ),
        (
            "folded block",
            "---\nname: delta\ndescription: >-\n  folded one\n  folded two\n---\nbody\n",
            ("delta", "folded one folded two"),
        ),
        (
            "literal block",
            "---\nname: epsilon\ndescription: |\n  literal one\n  literal two\n---\nbody\n",
            ("epsilon", "literal one\nliteral two"),
        ),
    ]


def test_frontmatter(mod) -> None:
    for label, text, (want_name, want_desc) in frontmatter_cases():
        got = mod.parse_skill_frontmatter(text)
        if got.get("name") == want_name and got.get("description") == want_desc:
            ok(f"frontmatter {label}")
        else:
            fail(f"frontmatter {label}", str(got))

    crlf = "\ufeff---\r\nname: zeta\r\ndescription: >-\r\n  crlf folded\r\n  second line\r\n---\r\nbody\r\n"
    got = mod.parse_skill_frontmatter(crlf)
    check(
        "frontmatter BOM+CRLF folded",
        got.get("name") == "zeta" and got.get("description") == "crlf folded second line",
        str(got),
    )

    got = mod.parse_skill_frontmatter("---\nname: eta\ndescription: unterminated\nbody\n")
    check("frontmatter unterminated returns empty", got == {}, str(got))

    got = mod.parse_skill_frontmatter("no frontmatter\n")
    check("frontmatter absent returns empty", got == {}, str(got))


def test_token_estimate(mod) -> None:
    check("tok_of ascii", mod.tok_of("abcd") == 1, str(mod.tok_of("abcd")))
    check("tok_of empty", mod.tok_of("") == 0)
    # 4 CJK chars = 12 UTF-8 bytes -> 3 tokens, not 1 char-based token.
    check("tok_of multibyte uses bytes", mod.tok_of("技能目录") == 3, str(mod.tok_of("技能目录")))


def test_catalog_summary(mod, tmp: Path) -> None:
    root = tmp / "summary" / "installed-plugins"
    write_skill(root, "plug-a/skills/dup", "name: shared\ndescription: plugin copy description")
    write_skill(root, "plug-b/skills/dup", "name: shared\ndescription: second plugin copy")
    write_skill(root, "plug-c/skills/only", "name: solo\ndescription: solo description")
    write_skill(
        root,
        "plug-d/skills/folded",
        "name: folded-skill\ndescription: >-\n  folded description\n  spans lines",
    )
    summary = mod.catalog_summary(root)
    check("summary counts every installed file", summary["skill_files"] == 4, str(summary))
    check("summary unique names", summary["unique_names"] == 3, str(summary))
    check("summary duplicate rows", summary["duplicate_rows"] == 1, str(summary))
    groups = summary["duplicate_name_groups"]
    check(
        "summary duplicate group names",
        groups and groups[0].get("name") == "shared" and groups[0].get("count") == 2,
        str(groups),
    )
    # Every row counts toward the estimate; the unique view keeps the first row only.
    check(
        "summary duplicate rows counted in total",
        summary["description_tokens"] > summary["unique_description_tokens"],
        f"{summary['description_tokens']} vs {summary['unique_description_tokens']}",
    )
    check(
        "summary folded description contributes length",
        summary["description_chars"]
        == sum(len(text) for text in [
            "second plugin copy",
            "plugin copy description",
            "solo description",
            "folded description spans lines",
        ]),
        str(summary["description_chars"]),
    )
    check(
        "summary deterministic across calls",
        mod.catalog_summary(root) == mod.catalog_summary(root),
        "non-deterministic summary",
    )
    files_n, tokens = mod.skill_catalog(root)
    check("skill_catalog file count", files_n == 4, str(files_n))
    check("skill_catalog summed tokens", tokens == summary["description_tokens"], str(tokens))

    empty = mod.catalog_summary(tmp / "does-not-exist")
    check(
        "summary missing root is zeroed",
        empty["skill_files"] == 0 and empty["description_tokens"] == 0,
        str(empty),
    )


def test_inventory_lines(mod, tmp: Path) -> None:
    grok_home = tmp / "inv" / "grok-home"
    user_home = tmp / "inv" / "user-home"
    secret = "sk-live-secret-should-not-appear"
    write(
        grok_home / "config.toml",
        'agent = "x"\n[mcp_servers.skillwiki]\nurl = "https://example.invalid/?token=leak"\n',
    )
    write(grok_home / "AGENTS.md", "rules\n")
    write_skill(
        grok_home,
        "installed-plugins/plug/skills/leaky",
        f"name: leaky\ndescription: >-\n  contains {secret}\n  and user@example.com",
    )
    write_skill(grok_home, "installed-plugins/plug/skills/leaky2", "name: leaky\ndescription: dup")

    lines = mod.inventory_lines(grok_home, user_home, 2)
    blob = "\n".join(lines)
    check("status keeps grok-catalog prefix", any(line.startswith("context: grok-catalog ") for line in lines), blob)
    catalog = next(line for line in lines if line.startswith("context: grok-catalog "))
    check("status labels static inventory", "static installed-plugin inventory" in catalog, catalog)
    check("status labels bytes/4 estimate", "UTF-8 bytes / 4" in catalog, catalog)
    check("status reports duplicate-name rows", "1 duplicate-name rows" in catalog, catalog)
    check("status reports unique names", "1 unique names" in catalog, catalog)
    check("status keeps discovered set unknown", any(line.startswith("context: grok-discovered UNKNOWN") for line in lines), blob)
    source = (ROOT / "skills" / "grok-build-harness" / "scripts" / "context_budget.py").read_text(
        encoding="utf-8"
    )
    check("status helper never shells out", "subprocess" not in source and "os.system" not in source, "shell call")
    check(
        "status does not echo description text",
        "contains" not in blob and "another description" not in blob,
        catalog,
    )
    check("status does not leak secrets", secret not in blob and "example.invalid" not in blob, blob)

    missing = "\n".join(mod.inventory_lines(tmp / "nope", tmp / "nope-user", None))
    check("status missing files reported", "context: grok/AGENTS.md missing" in missing, missing)
    check("status missing inspect stays unknown", "context: grok-discovered UNKNOWN" in missing, missing)


def main() -> int:
    mod = load_mod()
    tmp = Path(tempfile.mkdtemp(prefix="ctx-budget-"))
    try:
        test_frontmatter(mod)
        test_token_estimate(mod)
        test_catalog_summary(mod, tmp)
        test_inventory_lines(mod, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n=== Results: {PASS} passed, {FAIL} failed ===")
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
