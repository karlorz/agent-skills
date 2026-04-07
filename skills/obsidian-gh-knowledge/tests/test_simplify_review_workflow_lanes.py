import importlib.util
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


class SimplifyReviewWorkflowLaneTests(unittest.TestCase):
    def test_markdown_includes_workflow_lane_section_and_samples(self):
        data = {
            "generated_at": "2026-04-07 19:30",
            "output_path": "1️⃣-Index/vault-simplify-dedupe-review.md",
            "review": {
                "doctor": {"vault_name": "obsidian_vault"},
                "dashboard": {
                    "unresolved_links": 4,
                    "raw_inbox_items": 2,
                    "raw_inbox_path": "raw/inbox",
                    "curated_inbox_notes": 1,
                    "draft_notes": 1,
                    "files": 100,
                    "folders": 20,
                },
                "tasks": {"todo": 3, "done": 7},
            },
            "audit": {
                "issues": {
                    "missing_tldr": [],
                    "oversized_overviews": [],
                    "cleanup_inbox_backlog": [],
                }
            },
            "structure": {"counts": {"orphans": 1, "deadends": 2, "isolated": 0}},
            "dedupe": {
                "basename_groups": 0,
                "alias_groups": 0,
                "scope_notes": 12,
                "basename_duplicates": [],
                "alias_duplicates": [],
                "alias_scan_enabled": True,
            },
            "workflow": {
                "raw_inbox_paths": ["raw/inbox/source-a.md", "raw/inbox/source-b.md"],
                "inbox_paths": ["0️⃣-Inbox/curated-note.md"],
                "draft_paths": ["2️⃣-Drafts/draft-note.md"],
            },
            "flags": [],
        }

        rendered = LOCAL_MODULE._simplify_review_markdown(data, dedupe_limit=10)

        self.assertIn("## Workflow Lanes", rendered)
        self.assertIn("`raw/inbox`", rendered)
        self.assertIn("`0️⃣-Inbox`", rendered)
        self.assertIn("`2️⃣-Drafts`", rendered)
        self.assertIn("raw/inbox/source-a.md", rendered)
        self.assertIn("0️⃣-Inbox/curated-note.md", rendered)
        self.assertIn("2️⃣-Drafts/draft-note.md", rendered)


if __name__ == "__main__":
    unittest.main()
