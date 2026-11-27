#!/usr/bin/env python3
"""Contract and behavioral regression for deep-research vault write routing.

Static checks cover MCP-first precedence, frozen/MCP-only fail-closed behavior,
CAS publication receipts and readback, raw capture paths, ambiguous mutation
handling, local CLI opt-in scope, --save containment, README guidance, and
Codex parity. Behavioral checks extract the canonical containment guard from
references/vault-pipeline.md and exercise custom roots, conventional roots,
symlink aliases, outside targets, unresolved inventories, and the no-CLI rule.

Run:
    python3 skills/deep-research/scripts/test-vault-routing.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
_SKILL_MD = _SCRIPTS_DIR / ".." / "skills" / "deep-research" / "SKILL.md"
_VAULT_PIPELINE_MD = _SCRIPTS_DIR / ".." / "references" / "vault-pipeline.md"
_CODEX_TOOLS_MD = _SCRIPTS_DIR / ".." / "references" / "codex-tools.md"
_README_MD = _SCRIPTS_DIR / ".." / "README.md"

_GUARD_BEGIN = "# BEGIN deep-research containment guard"
_GUARD_END = "# END deep-research containment guard"


def _read(path: Path) -> str:
    if not path.is_file():
        raise FileNotFoundError(f"contract file not found: {path}")
    return path.read_text(encoding="utf-8")


def _norm(text: str) -> str:
    """Compare prose contracts without coupling them to Markdown wrapping."""
    return " ".join(text.split())


def _extract_guard(text: str, label: str) -> str:
    if text.count(_GUARD_BEGIN) != 1 or text.count(_GUARD_END) != 1:
        raise AssertionError(
            f"{label} must contain exactly one canonical containment guard block"
        )
    code = text.split(_GUARD_BEGIN, 1)[1].split(_GUARD_END, 1)[0]
    return textwrap.dedent(code).strip() + "\n"


class VaultRoutingContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.skill = _read(_SKILL_MD)
        cls.vault = _read(_VAULT_PIPELINE_MD)
        cls.codex = _read(_CODEX_TOOLS_MD)
        cls.readme = _read(_README_MD)
        cls.skill_n = _norm(cls.skill)
        cls.vault_n = _norm(cls.vault)
        cls.codex_n = _norm(cls.codex)
        cls.readme_n = _norm(cls.readme)

    def assert_phrase(self, text: str, phrase: str) -> None:
        self.assertTrue(
            _norm(phrase) in text,
            f"missing phrase: {phrase!r}",
        )

    def test_mcp_route_precedes_local_cli(self) -> None:
        self.assert_phrase(self.skill_n, "Resolve the vault write route first")
        self.assert_phrase(self.skill_n, "precedes vault detection")
        self.assert_phrase(self.skill_n, "no local CLI readiness requirement")
        self.assert_phrase(self.skill_n, "do not run `skillwiki path`")
        self.assert_phrase(self.skill_n, "supplies the `default_vault`")
        self.assert_phrase(self.skill_n, "single routing home")
        self.assert_phrase(self.vault_n, "Advertised SkillWiki HTTP MCP wins")
        self.assert_phrase(self.vault_n, "no local CLI readiness requirement")
        self.assert_phrase(self.vault_n, "do not run `skillwiki lang`")
        self.assert_phrase(self.vault_n, "handshake's `default_vault`")
        self.assert_phrase(self.vault_n, "single routing home")
        self.assert_phrase(self.vault_n, "after the MCP route is ruled out")
        self.assert_phrase(self.vault_n, "only as part of that opted-in local route")

        route = self.vault_n.find("Advertised SkillWiki HTTP MCP wins")
        local = self.vault_n.find("## Local CLI authoring route")
        raw = self.vault_n.find("## Raw Capture")
        publish = self.vault_n.find("## Typed-Page Publication (MCP CAS)")
        containment = self.vault_n.find("## Containment boundary")
        self.assertGreaterEqual(route, 0, "MCP route rule is missing")
        self.assertGreater(local, route, "local CLI route must follow the MCP route")
        self.assertGreaterEqual(raw, 0, "raw capture route is missing")
        self.assertGreaterEqual(publish, 0, "MCP publication route is missing")
        self.assertLess(
            raw,
            local,
            "raw capture route must precede the local CLI route",
        )
        self.assertLess(
            publish,
            local,
            "MCP publication route must precede the local CLI route",
        )
        self.assertGreater(
            containment,
            local,
            "containment boundary must follow route resolution",
        )

        optin_probe = self.vault_n.find("`skillwiki path --plain` once")
        self.assertGreater(
            optin_probe,
            local,
            "CLI path probe must sit inside the explicit local opt-in section",
        )
        self.assertNotIn(
            "skillwiki path --plain",
            self.vault_n[containment:],
            "containment boundary must not probe the CLI",
        )

        skill_route = self.skill_n.find("Resolve the vault write route first")
        skill_scratch_probe = self.skill_n.find("skillwiki path --plain")
        self.assertGreaterEqual(skill_route, 0, "SKILL route resolution is missing")
        self.assertGreater(
            skill_scratch_probe,
            skill_route,
            "SKILL must state the scratch CLI prohibition after route resolution",
        )
        self.assertNotIn(
            "$(skillwiki path",
            self.skill,
            "SKILL must not invoke skillwiki path in the scratch pipeline",
        )
        self.assertNotIn(
            "skillwiki path --plain 2>/dev/null",
            self.skill,
            "SKILL must not probe skillwiki path for containment",
        )

    def test_frozen_or_mcp_only_leaf_fails_closed(self) -> None:
        for phrase in (
            ".WIKI_GIT_FROZEN",
            "MCP-only leaf",
            "missing MCP mutation tool is a hard stop",
            "fails closed with the draft outside the vault",
            "No local fallback, auto `skillwiki init`, install, or git",
            "Do not initialize, install, clone, or git-sync",
        ):
            self.assert_phrase(self.vault_n, phrase)

        self.assert_phrase(
            self.skill_n,
            "A frozen or MCP-only leaf that lacks a required MCP mutation fails closed",
        )
        self.assert_phrase(self.skill_n, "keep the draft outside the vault")
        self.assert_phrase(self.skill_n, "Never fall back to a local CLI")
        self.assert_phrase(self.skill_n, "no local fallback")
        self.assert_phrase(self.skill_n, "no init/install/git")

        for text in (self.skill_n, self.vault_n, self.codex_n):
            self.assertNotIn("advisory to run `skillwiki init`", text)
            self.assertNotIn("If it returns a valid vault, default to vault mode", text)

    def test_cas_publication_receipts_and_readback(self) -> None:
        for phrase in (
            "wiki_page_publish",
            "Read the exact target path first",
            "base_sha256",
            "FILE_CHANGED",
            "re-read the target, rebase the draft on the current bytes, and retry once",
            "require the receipt to report `ok: true`, the intended `vault_id`, and the exact `path`",
            "A mismatched vault or path is not a save",
            "Read back the exact path with `wiki_read_page`",
            "SHA-256 of the exact bytes sent",
            "s3_verified",
            "wiki_log_append",
            "event_path",
        ):
            self.assert_phrase(self.vault_n, phrase)

        read = self.vault_n.find("Read the exact target path first")
        publish = self.vault_n.find("Call `wiki_page_publish` with `path`")
        receipt = self.vault_n.find("require the receipt")
        readback = self.vault_n.find("Read back the exact path")
        self.assertGreaterEqual(read, 0)
        self.assertGreater(publish, read, "publish must follow the CAS read")
        self.assertGreater(receipt, publish, "receipt check must follow publish")
        self.assertGreater(readback, receipt, "readback must follow receipt check")

    def test_workitem_cas_preserves_proposed_intent(self) -> None:
        for phrase in (
            "wiki_workitem_write",
            "base_sha256",
            "FILE_CHANGED",
            "authorized MCP task capture",
            "status: proposed",
            "must not promote a work item to `in-progress`",
            "leave lifecycle decisions to the execution workflow",
        ):
            self.assert_phrase(self.vault_n, phrase)

        self.assert_phrase(
            self.skill_n,
            "`wiki_workitem_write` CAS when advertised",
        )
        self.assert_phrase(
            self.skill_n,
            "never promote a work item to `in-progress`",
        )

    def test_raw_capture_uses_returned_transcript_paths(self) -> None:
        for phrase in (
            "`wiki_capture`",
            '`kind: "note"`',
            "raw/transcripts/",
            "Verify the returned `path`",
            "exact returned `raw/transcripts/...` path",
            "Never invent `raw/articles/...`",
            "`--no-raw` skips capture and records the provenance gap",
            "using-skillwiki/references/save-attachments.md",
        ):
            self.assert_phrase(self.vault_n, phrase)

        self.assertNotIn("Write to `raw/articles/<slug>.md`", self.vault_n)
        self.assertNotIn("raw/assets/<dated-slug>/", self.vault_n)
        self.assertNotIn("ingested_by", self.vault_n)

    def test_ambiguous_mutation_has_no_resend(self) -> None:
        for phrase in (
            "Ambiguous mutation",
            "Do not resend the mutation",
            "only when the exact target or a returned path is known",
            "exactly one reconcile `wiki_read_page`",
            "timeout, transport drop",
            "do not guess a path",
            "report the capture/event as unverified",
            "same no-resend rule applies to `wiki_capture`, `wiki_workitem_write`, `wiki_log_append`, and `wiki_page_publish`",
        ):
            self.assert_phrase(self.vault_n, phrase)

        self.assert_phrase(
            self.skill_n,
            "one reconcile `wiki_read_page` only when the exact target or a returned path is known",
        )
        self.assert_phrase(
            self.skill_n,
            "MCP mutation result is ambiguous and no exact target or returned path exists",
        )

    def test_save_containment_guard(self) -> None:
        for phrase in (
            "Containment boundary",
            "DEEP_RESEARCH_VAULT_ROOT",
            "DEEP_RESEARCH_PROTECTED_ROOTS",
            "`$HOME/wiki`",
            "`$HOME/wiki-git`",
            "resolves the destination through symlinks",
            "Fail closed when the boundary inventory is unresolved",
            "CONTAINMENT_UNRESOLVED",
            "CONTAINMENT_BLOCKED",
            "never invokes `skillwiki`",
            "only the explicit operator-opted local",
            "before creating parent directories or writing",
            "Path(expanded).resolve(strict=False)",
        ):
            self.assert_phrase(self.vault_n, phrase)

        self.assert_phrase(self.skill_n, "canonical containment guard")
        self.assert_phrase(
            self.skill_n,
            "fails closed when the boundary inventory is unresolved",
        )
        self.assert_phrase(self.skill_n, "never invokes the CLI")
        self.assertNotIn("skillwiki path --plain 2>/dev/null", self.skill)
        self.assertNotIn('VAULT_ROOT="$(skillwiki path', self.skill)

        guard_code = _extract_guard(self.vault, "vault-pipeline.md")
        for token in ("skillwiki", "subprocess", "os.system", "Popen"):
            self.assertNotIn(token, guard_code)
        self.assertLess(
            self.vault.find(_GUARD_BEGIN),
            self.vault.find("## `--save` containment guard"),
            "canonical guard must be defined before the --save section",
        )

    def test_local_optin_scope_is_publication_only(self) -> None:
        for phrase in (
            "Scope of the opt-in",
            "authorizes typed-page publication only",
            "does not authorize raw capture, binary ingress, or follow-up work-item creation",
            "requires existing verified provenance",
            "If provenance is not already verified, do not publish",
            "raw capture and follow-up work items remain MCP-required or retained as gaps",
        ):
            self.assert_phrase(self.vault_n, phrase)

        self.assert_phrase(
            self.skill_n,
            "raw capture and follow-up work items remain MCP-required or retained as gaps",
        )

    def test_codex_parity_and_single_routing_home(self) -> None:
        self.assert_phrase(self.codex_n, "references/vault-pipeline.md")
        self.assert_phrase(self.codex_n, "single routing home")
        self.assert_phrase(self.codex_n, "Advertised SkillWiki MCP tools win")
        self.assert_phrase(self.codex_n, "same containment guard")
        self.assert_phrase(self.codex_n, "session-known")
        self.assert_phrase(self.codex_n, "never invokes `skillwiki`")

        for phrase in (
            "safe inside a Codex sandbox",
            "commit in place",
            "Create branch",
            "Hand off to local",
            "Environment Detection",
            "detached HEAD",
        ):
            self.assertNotIn(phrase, self.codex_n)

    def test_readme_reflects_mcp_route(self) -> None:
        self.assert_phrase(self.readme_n, "MCP vault route when advertised")
        self.assert_phrase(self.readme_n, "Advertised SkillWiki HTTP MCP tools win")
        self.assert_phrase(self.readme_n, "containment guard")
        self.assert_phrase(self.readme_n, "already-verified provenance")
        self.assert_phrase(
            self.readme_n,
            "raw capture and follow-up work items require MCP mutations",
        )
        self.assertNotIn("auto-detects vault via `skillwiki path`", self.readme_n)
        self.assertNotIn("Vault auto-detection", self.readme_n)
        self.assertNotIn("errors if no vault is configured", self.readme_n)
        self.assertNotIn("delegates transactional publication", self.readme_n)
        self.assertNotIn("vault lock or publication stalls", self.readme_n)

    def test_removed_local_writer_advice_absent(self) -> None:
        unsafe = (
            "wiki-add-task",
            "Write to `raw/articles/<slug>.md`",
            "raw/assets/<dated-slug>/",
            'ingested_by: "deep-research"',
            "status: proposed` → `status: in-progress`",
            "common fix: `kind: task` → `kind: feature`",
            "advisory to run `skillwiki init`",
            "Vault not configured (auto mode)",
            "Vault not configured (`--vault` flag)",
            "Vault mode: publisher capability is unavailable",
            "Vault publisher capability or publication fails",
            "Otherwise run `skillwiki path`",
            "If NO_VAULT_CONFIGURED, use stdout",
            "If vault mode active: run `skillwiki lang`",
            "Vault mode composes pages as unpublished drafts",
            "delegates taxonomy, final page publication, index, and log updates to `skillwiki page publish`",
            "safe inside a Codex sandbox",
            "commit in place",
            "filesystem-safe",
            "detached HEAD",
            "detached-HEAD",
            "Git commit includes all artifacts in a single atomic commit",
            "Do NOT invoke `wiki-add-task`",
            "Raw follow-up captures use this frontmatter",
            "run `skillwiki lang` for output language",
        )
        for label, text in (
            ("SKILL.md", self.skill_n),
            ("vault-pipeline.md", self.vault_n),
            ("codex-tools.md", self.codex_n),
        ):
            for phrase in unsafe:
                self.assertNotIn(phrase, text, f"{label} still contains: {phrase!r}")


class ContainmentGuardBehavior(unittest.TestCase):
    """Exercise the guard extracted from vault-pipeline.md, not a reimplementation."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.vault_text = _read(_VAULT_PIPELINE_MD)
        cls.skill_text = _read(_SKILL_MD)
        cls.guard_code = _extract_guard(cls.vault_text, "vault-pipeline.md")
        cls._tmp = tempfile.TemporaryDirectory()
        cls.guard_path = Path(cls._tmp.name) / "containment_guard.py"
        cls.guard_path.write_text(cls.guard_code, encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(dir=self._tmp.name))
        self.home = self.root / "home"
        (self.home / "wiki").mkdir(parents=True)
        (self.home / "wiki-git").mkdir()
        self.custom = self.root / "custom-vault"
        (self.custom / "queries").mkdir(parents=True)
        self.outside = self.root / "outside"
        self.outside.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()

    def _run(
        self,
        target: Path | str,
        *,
        home: str | None = None,
        vault_root: str | None = None,
        protected_roots: str | None = None,
        path_prefix: Path | None = None,
        extra_env: dict[str, str] | None = None,
        cwd: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.pop("DEEP_RESEARCH_VAULT_ROOT", None)
        env.pop("DEEP_RESEARCH_PROTECTED_ROOTS", None)
        env["HOME"] = str(self.home) if home is None else home
        if vault_root is not None:
            env["DEEP_RESEARCH_VAULT_ROOT"] = vault_root
        if protected_roots is not None:
            env["DEEP_RESEARCH_PROTECTED_ROOTS"] = protected_roots
        if path_prefix is not None:
            env["PATH"] = str(path_prefix) + os.pathsep + env.get("PATH", "")
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [sys.executable, str(self.guard_path), str(target)],
            env=env,
            cwd=str(cwd) if cwd is not None else None,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_verdict(
        self,
        result: subprocess.CompletedProcess[str],
        verdict: str,
        *,
        code: int,
    ) -> None:
        self.assertEqual(result.returncode, code, result.stderr)
        self.assertEqual(result.stdout.strip(), verdict)

    def test_custom_vault_root_blocks_inside_and_allows_outside(self) -> None:
        result = self._run(
            self.custom / "queries" / "report.md",
            vault_root=str(self.custom),
        )
        self.assert_verdict(result, "inside", code=1)
        self.assertIn("CONTAINMENT_BLOCKED", result.stderr)

        result = self._run(self.custom, vault_root=str(self.custom))
        self.assert_verdict(result, "inside", code=1)

        result = self._run(self.outside / "report.md", vault_root=str(self.custom))
        self.assert_verdict(result, "outside", code=0)

    def test_conventional_home_roots_block(self) -> None:
        for name in ("wiki", "wiki-git"):
            result = self._run(self.home / name / "report.md")
            self.assert_verdict(result, "inside", code=1)
            self.assertIn("CONTAINMENT_BLOCKED", result.stderr)

        result = self._run(self.home / "wiki")
        self.assert_verdict(result, "inside", code=1)

        result = self._run("~/wiki/report.md")
        self.assert_verdict(result, "inside", code=1)

        result = self._run(self.outside / "report.md")
        self.assert_verdict(result, "outside", code=0)

    def test_symlink_aliases_block(self) -> None:
        alias = self.root / "wiki-alias"
        alias.symlink_to(self.home / "wiki", target_is_directory=True)
        result = self._run(alias / "report.md")
        self.assert_verdict(result, "inside", code=1)

        vault_alias = self.root / "vault-alias"
        vault_alias.symlink_to(self.custom, target_is_directory=True)
        result = self._run(
            self.custom / "queries" / "report.md",
            vault_root=str(vault_alias),
        )
        self.assert_verdict(result, "inside", code=1)

        (self.home / "wiki" / "report.md").write_text("evidence", encoding="utf-8")
        linked_target = self.outside / "linked-report.md"
        linked_target.symlink_to(self.home / "wiki" / "report.md")
        result = self._run(linked_target)
        self.assert_verdict(result, "inside", code=1)

    def test_outside_target_allowed(self) -> None:
        extra = self.root / "extra-mirror"
        extra.mkdir()
        result = self._run(
            self.outside / "report.md",
            vault_root=str(self.custom),
            protected_roots=str(extra),
        )
        self.assert_verdict(result, "outside", code=0)

    def test_relative_target_resolves_against_cwd(self) -> None:
        result = self._run("report.md", cwd=self.outside)
        self.assert_verdict(result, "outside", code=0)

        result = self._run("report.md", cwd=self.home / "wiki")
        self.assert_verdict(result, "inside", code=1)

    def test_protected_root_list_blocks_each_entry(self) -> None:
        first = self.root / "mirror-one"
        second = self.root / "mirror-two"
        first.mkdir()
        second.mkdir()
        roots = os.pathsep.join((str(first), str(second)))
        for root in (first, second):
            result = self._run(root / "report.md", protected_roots=roots)
            self.assert_verdict(result, "inside", code=1)
        result = self._run(self.outside / "report.md", protected_roots=roots)
        self.assert_verdict(result, "outside", code=0)

    def test_unresolved_boundary_fails_closed(self) -> None:
        result = self._run(self.outside / "report.md", home="")
        self.assert_verdict(result, "error", code=2)
        self.assertIn("CONTAINMENT_UNRESOLVED", result.stderr)

        result = self._run(self.outside / "report.md", vault_root="relative/vault")
        self.assert_verdict(result, "error", code=2)

        result = self._run(
            self.outside / "report.md",
            vault_root="NO_VAULT_CONFIGURED",
        )
        self.assert_verdict(result, "error", code=2)

        result = self._run(self.outside / "report.md", home="", protected_roots="")
        self.assert_verdict(result, "error", code=2)

    def test_guard_never_invokes_cli(self) -> None:
        marker = self.root / "cli-called"
        fake = self.bin / "skillwiki"
        fake.write_text(
            "#!/bin/sh\n"
            'printf called >> "$FAKE_CLI_MARKER"\n'
            "exit 0\n",
            encoding="utf-8",
        )
        fake.chmod(0o755)

        for target in (
            self.custom / "queries" / "report.md",
            self.outside / "report.md",
        ):
            result = self._run(
                target,
                vault_root=str(self.custom),
                path_prefix=self.bin,
                extra_env={"FAKE_CLI_MARKER": str(marker)},
            )
            self.assertIn(result.returncode, (0, 1), result.stderr)
        self.assertFalse(
            marker.exists(),
            "containment guard invoked the skillwiki CLI",
        )

    def test_skill_guard_matches_canonical_copy(self) -> None:
        skill_guard = _extract_guard(self.skill_text, "SKILL.md")
        self.assertEqual(
            skill_guard,
            self.guard_code,
            "SKILL.md scratch guard must stay identical to the canonical "
            "vault-pipeline.md guard",
        )


if __name__ == "__main__":
    unittest.main()
