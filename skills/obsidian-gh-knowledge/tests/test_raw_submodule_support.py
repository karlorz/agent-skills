import importlib.util
import subprocess
import tempfile
import unittest
from unittest import mock
from pathlib import Path


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


INIT_MODULE = _load_module(
    "obsidian_init_local_vault",
    "/Users/karlchow/Documents/obsidian_vault/agent-skills/skills/obsidian-gh-knowledge/scripts/init_local_vault.py",
)
LOCAL_MODULE = _load_module(
    "obsidian_local_knowledge",
    "/Users/karlchow/Documents/obsidian_vault/agent-skills/skills/obsidian-gh-knowledge/scripts/local_obsidian_knowledge.py",
)


class InitLocalVaultTests(unittest.TestCase):
    def test_relative_submodule_path_accepts_simple_path(self):
        self.assertEqual(INIT_MODULE._relative_submodule_path("raw"), "raw")
        self.assertEqual(INIT_MODULE._relative_submodule_path("raw/inbox"), "raw/inbox")

    def test_relative_submodule_path_rejects_parent_traversal(self):
        with self.assertRaises(SystemExit):
            INIT_MODULE._relative_submodule_path("../raw")

    def test_bootstrap_repo_git_sets_worktree_push_recurse_submodules(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.run(["git", "init"], cwd=tmpdir, check=True, capture_output=True, text=True)

            actions = INIT_MODULE._bootstrap_repo_git(tmpdir, dry_run=False)

            self.assertIn("set worktree-local push.recurseSubmodules=on-demand", actions)

            worktree_value = subprocess.run(
                ["git", "config", "--show-origin", "--get", "push.recurseSubmodules"],
                cwd=tmpdir,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            self.assertIn("config.worktree", worktree_value)
            self.assertTrue(worktree_value.endswith("\ton-demand"))

            extension_value = subprocess.run(
                ["git", "config", "--show-origin", "--get", "extensions.worktreeConfig"],
                cwd=tmpdir,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            self.assertTrue(extension_value.endswith("\ttrue"))

    def test_bootstrap_existing_raw_submodule_skips_missing_dry_run_dir(self):
        missing_dir = str(Path(tempfile.gettempdir()) / "obsidian-gh-missing-bootstrap")
        actions, configured_origin = INIT_MODULE._bootstrap_existing_raw_submodule(
            missing_dir,
            raw_submodule_path="raw",
            dry_run=True,
        )

        self.assertEqual(actions, [])
        self.assertIsNone(configured_origin)


class CaptureRawNoteTests(unittest.TestCase):
    def test_capture_raw_note_writes_markdown_inside_raw_submodule(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_dir = Path(tmpdir)
            (vault_dir / "raw" / "inbox").mkdir(parents=True)

            LOCAL_MODULE._capture_raw_note(
                vault_dir,
                title="Example Source",
                folder="raw/inbox",
                name=None,
                body="Copied source content.",
                source="https://example.com/post",
                extension="md",
                overwrite=False,
                dry_run=False,
            )

            created = vault_dir / "raw" / "inbox" / "example-source.md"
            self.assertTrue(created.exists())
            content = created.read_text(encoding="utf-8")
            self.assertIn("# Example Source", content)
            self.assertIn("Source: https://example.com/post", content)
            self.assertIn("Copied source content.", content)

    def test_capture_raw_note_rejects_non_raw_destination(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_dir = Path(tmpdir)
            (vault_dir / "0️⃣-Inbox").mkdir(parents=True)

            with self.assertRaises(SystemExit):
                LOCAL_MODULE._capture_raw_note(
                    vault_dir,
                    title="Bad Target",
                    folder="0️⃣-Inbox",
                    name=None,
                    body="Should fail.",
                    source=None,
                    extension="md",
                    overwrite=False,
                    dry_run=False,
                )


class DoctorFallbackTests(unittest.TestCase):
    def test_doctor_data_reports_git_state_when_obsidian_cli_is_unavailable(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_dir = Path(tmpdir)
            subprocess.run(["git", "init"], cwd=tmpdir, check=True, capture_output=True, text=True)
            INIT_MODULE._bootstrap_repo_git(tmpdir, dry_run=False)

            with mock.patch.object(LOCAL_MODULE, "_load_config", return_value={"vault_name": "Test Vault"}):
                with mock.patch.object(LOCAL_MODULE, "_obsidian_command", side_effect=SystemExit(2)):
                    with mock.patch.object(LOCAL_MODULE, "_obsidian_binary_optional", return_value=None):
                        data = LOCAL_MODULE._doctor_data(vault_dir)

            self.assertFalse(data["cli_ready"])
            self.assertEqual(data["obsidian_binary"], "(unavailable)")
            self.assertTrue(data["git_ready"])
            self.assertEqual(data["push_recurse_submodules"], "on-demand")
            self.assertIn("config.worktree", data["push_recurse_submodules_origin"])


if __name__ == "__main__":
    unittest.main()
