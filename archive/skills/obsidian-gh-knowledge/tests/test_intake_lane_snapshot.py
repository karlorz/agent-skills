import importlib.util
import tempfile
import unittest
from pathlib import Path


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


LOCAL_MODULE = _load_module(
    "obsidian_local_knowledge",
    "/Users/karlchow/Documents/obsidian_vault/agent-skills/skills/obsidian-gh-knowledge/scripts/local_obsidian_knowledge.py",
)


class IntakeLaneSnapshotTests(unittest.TestCase):
    def test_snapshot_distinguishes_raw_intake_from_curated_inbox(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_dir = Path(tmpdir)
            (vault_dir / "raw" / "inbox").mkdir(parents=True)
            (vault_dir / "0️⃣-Inbox").mkdir()
            (vault_dir / "2️⃣-Drafts").mkdir()

            (vault_dir / "raw" / "inbox" / "source-a.md").write_text("# Source A\n", encoding="utf-8")
            (vault_dir / "raw" / "inbox" / "source-b.md").write_text("# Source B\n", encoding="utf-8")
            (vault_dir / "0️⃣-Inbox" / "curated-note.md").write_text("# Curated\n", encoding="utf-8")
            (vault_dir / "2️⃣-Drafts" / "draft-note.md").write_text("# Draft\n", encoding="utf-8")

            snapshot = LOCAL_MODULE._intake_lane_snapshot(vault_dir)

            self.assertEqual(snapshot["raw_inbox_items"], 2)
            self.assertEqual(snapshot["curated_inbox_notes"], 1)
            self.assertEqual(snapshot["draft_notes"], 1)
            self.assertEqual(
                snapshot["raw_inbox_paths"],
                ["raw/inbox/source-a.md", "raw/inbox/source-b.md"],
            )
            self.assertEqual(snapshot["curated_inbox_paths"], ["0️⃣-Inbox/curated-note.md"])
            self.assertEqual(snapshot["draft_paths"], ["2️⃣-Drafts/draft-note.md"])

    def test_snapshot_ignores_hidden_and_archived_paths(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_dir = Path(tmpdir)
            (vault_dir / "raw" / "inbox" / ".hidden").mkdir(parents=True)
            (vault_dir / "raw" / "inbox" / "_archive").mkdir(parents=True)
            (vault_dir / "0️⃣-Inbox" / "_archive").mkdir(parents=True)
            (vault_dir / "2️⃣-Drafts" / ".hidden").mkdir(parents=True)

            (vault_dir / "raw" / "inbox" / ".hidden" / "skip.md").write_text("# Hidden\n", encoding="utf-8")
            (vault_dir / "raw" / "inbox" / "_archive" / "skip.md").write_text("# Archived\n", encoding="utf-8")
            (vault_dir / "0️⃣-Inbox" / "_archive" / "skip.md").write_text("# Archived curated\n", encoding="utf-8")
            (vault_dir / "2️⃣-Drafts" / ".hidden" / "skip.md").write_text("# Hidden draft\n", encoding="utf-8")

            snapshot = LOCAL_MODULE._intake_lane_snapshot(vault_dir)

            self.assertEqual(snapshot["raw_inbox_items"], 0)
            self.assertEqual(snapshot["curated_inbox_notes"], 0)
            self.assertEqual(snapshot["draft_notes"], 0)


if __name__ == "__main__":
    unittest.main()
