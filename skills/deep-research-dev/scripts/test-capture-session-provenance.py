#!/usr/bin/env python3
"""Regression suite for deep-research-dev session provenance capture.

Uses a synthetic Grok sessions tree only. The helper must decode JSONL user
records, freeze one matched summary, count tool calls from decoded history, and
fail closed for ambiguous or malformed observations.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
HELPER = SCRIPTS / "capture-session-provenance.py"
PREFIX = "/deep-research-dev:deep-research-dev --ephemeral --unattended "
FRAMING = (
    "\n\nWhen the research report is complete, print a line exactly:\n"
    "===REPORT===\nthen print the final report only (no tool narration)."
)
STARTED = "2026-08-13T10:00:00Z"


def prompt(query: str) -> str:
    return PREFIX + query + FRAMING


def write_session(
    root: Path,
    name: str,
    *,
    query: str,
    created_at: str = "2026-08-13T10:00:00.500000Z",
    agent_name: str = "grok-build-plan",
    model: str = "deepseek-v4-flash-max",
    content_shape: str = "blocks",
    record_type: str = "user",
    exact_prompt: str | None = None,
    wrap_user_query: bool = False,
    trailing_whitespace: bool = False,
    split_prompt_blocks: bool = False,
) -> Path:
    session = root / name
    session.mkdir(parents=True)
    summary = {
        "agent_name": agent_name,
        "current_model_id": model,
        "created_at": created_at,
    }
    (session / "summary.json").write_text(json.dumps(summary) + "\n", encoding="utf-8")
    text = exact_prompt if exact_prompt is not None else prompt(query)
    if trailing_whitespace:
        text += "\n\n"
    if wrap_user_query:
        text = f"<user_query>\n{text}\n</user_query>"
    if content_shape == "blocks":
        if split_prompt_blocks:
            midpoint = len(text) // 2
            content: object = [
                {"type": "text", "text": text[:midpoint]},
                {"type": "text", "text": text[midpoint:]},
            ]
        else:
            content = [{"type": "text", "text": text}]
    elif content_shape == "legacy":
        content = text
    else:
        raise ValueError(content_shape)
    records = [
        {"type": record_type, "content": content},
        {
            "type": "assistant",
            "content": "",
            "tool_calls": [
                {"name": "web_fetch", "arguments": "{}"},
                {"name": "grok-search", "arguments": "{}"},
                {"name": "web_fetch", "arguments": "{}"},
            ],
        },
    ]
    (session / "chat_history.jsonl").write_text(
        "".join(json.dumps(record) + "\n" for record in records), encoding="utf-8"
    )
    return session


def run(
    root: Path,
    before: Path,
    output: Path,
    query: str | None = None,
    *,
    prompt_file: Path | None = None,
    started: str = STARTED,
) -> tuple[int, dict[str, object], str]:
    cmd = [
        sys.executable,
        str(HELPER),
        "resolve",
        "--sessions-root",
        str(root),
        "--before",
        str(before),
        "--started",
        started,
        "--output",
        str(output),
        "--frozen-summary",
        str(output.parent / "session-summary.json"),
    ]
    if query is not None:
        cmd.extend(["--query", query])
    if prompt_file is not None:
        cmd.extend(["--prompt-file", str(prompt_file)])
    completed = subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    res_dict = {}
    if output.is_file():
        try:
            res_dict = json.loads(output.read_text(encoding="utf-8"))
        except Exception:
            pass
    return completed.returncode, res_dict, completed.stderr


def snapshot(root: Path, output: Path) -> tuple[int, str]:
    completed = subprocess.run(
        [
            sys.executable,
            str(HELPER),
            "snapshot",
            "--sessions-root",
            str(root),
            "--output",
            str(output),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return completed.returncode, completed.stderr


def main() -> int:
    if not HELPER.is_file():
        print(f"RED: provenance helper is missing: {HELPER}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="test-capture-session-provenance-") as temp:
        root = Path(temp) / "sessions"
        root.mkdir()
        snapshot_file = Path(temp) / "snapshot.txt"
        code, stderr = snapshot(root, snapshot_file)
        assert code == 0, (code, stderr)
        assert snapshot_file.read_text(encoding="utf-8") == ""
        (root / "pre-existing").mkdir()
        code, stderr = snapshot(root, snapshot_file)
        assert code == 0, (code, stderr)
        assert snapshot_file.read_text(encoding="utf-8") == "pre-existing\n"

        before = Path(temp) / "before.txt"
        before.write_text("old-session\n", encoding="utf-8")
        query = "multiline query\n\nwith a real newline"
        session = write_session(root, "fresh", query=query)
        output = Path(temp) / "result.json"
        code, result, stderr = run(root, before, output, query)
        assert code == 0, (code, stderr, result)
        assert result["actual_model"] == "deepseek-v4-flash-max", result
        assert result["session_id"] == "fresh", result
        assert result["session_provenance"] == {
            "session_id": "fresh",
            "created_at": "2026-08-13T10:00:00.500000Z",
            "agent_name": "grok-build-plan",
            "current_model_id": "deepseek-v4-flash-max",
            "summary_sha256": hashlib.sha256((session / "summary.json").read_bytes()).hexdigest(),
        }, result
        assert result["tool_counts"] == {"grok-search": 1, "web_fetch": 2}, result
        frozen = output.parent / "session-summary.json"
        assert frozen.read_bytes() == (session / "summary.json").read_bytes()

        root_wrapped = Path(temp) / "wrapped-sessions"
        root_wrapped.mkdir()
        before_wrapped = Path(temp) / "before-wrapped.txt"
        before_wrapped.write_text("", encoding="utf-8")
        write_session(root_wrapped, "wrapped", query="wrapped", wrap_user_query=True)
        code, result, stderr = run(root_wrapped, before_wrapped, Path(temp) / "wrapped.json", "wrapped")
        assert code == 0, (code, stderr, result)
        assert result["session_id"] == "wrapped", result

        root_split = Path(temp) / "split-sessions"
        root_split.mkdir()
        before_split = Path(temp) / "before-split.txt"
        before_split.write_text("", encoding="utf-8")
        write_session(
            root_split,
            "split",
            query="split prompt",
            split_prompt_blocks=True,
            trailing_whitespace=True,
        )
        code, result, stderr = run(root_split, before_split, Path(temp) / "split.json", "split prompt")
        assert code == 0, (code, stderr, result)
        assert result["session_id"] == "split", result

        root_lowercase_z = Path(temp) / "lowercase-z-sessions"
        root_lowercase_z.mkdir()
        before_lowercase_z = Path(temp) / "before-lowercase-z.txt"
        before_lowercase_z.write_text("", encoding="utf-8")
        write_session(
            root_lowercase_z,
            "lowercase-z",
            query="lowercase-z",
            created_at="2026-08-13T10:00:00.500000z",
        )
        code, result, stderr = run(
            root_lowercase_z,
            before_lowercase_z,
            Path(temp) / "lowercase-z.json",
            "lowercase-z",
        )
        assert code == 0, (code, stderr, result)
        assert result["session_id"] == "lowercase-z", result

        root_legacy = Path(temp) / "legacy-sessions"
        root_legacy.mkdir()
        before_legacy = Path(temp) / "before-legacy.txt"
        before_legacy.write_text("", encoding="utf-8")
        write_session(root_legacy, "legacy", query="legacy", content_shape="legacy")
        code, result, stderr = run(root_legacy, before_legacy, Path(temp) / "legacy.json", "legacy")
        assert code == 0, (code, stderr, result)
        assert result["session_provenance"]["agent_name"] == "grok-build-plan", result

        root_tool = Path(temp) / "tool-sessions"
        root_tool.mkdir()
        before_tool = Path(temp) / "before-tool.txt"
        before_tool.write_text("", encoding="utf-8")
        write_session(root_tool, "tool", query="tool", record_type="tool_result")
        code, result, stderr = run(root_tool, before_tool, Path(temp) / "tool.json", "tool")
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None and "no matching" in result["observation_error"], result

        root_prefix = Path(temp) / "prefix-sessions"
        root_prefix.mkdir()
        before_prefix = Path(temp) / "before-prefix.txt"
        before_prefix.write_text("", encoding="utf-8")
        write_session(root_prefix, "prefix", query="same", exact_prompt=prompt("same extra"))
        code, result, stderr = run(root_prefix, before_prefix, Path(temp) / "prefix.json", "same")
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None and "no matching" in result["observation_error"], result

        root_many = Path(temp) / "many-sessions"
        root_many.mkdir()
        before_many = Path(temp) / "before-many.txt"
        before_many.write_text("", encoding="utf-8")
        write_session(root_many, "one", query="many")
        write_session(root_many, "two", query="many")
        code, result, stderr = run(root_many, before_many, Path(temp) / "many.json", "many")
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None and "ambiguous" in result["observation_error"], result

        root_old = Path(temp) / "old-sessions"
        root_old.mkdir()
        before_old = Path(temp) / "before-old.txt"
        before_old.write_text("", encoding="utf-8")
        write_session(root_old, "old", query="old", created_at="2026-08-13T09:59:59Z")
        code, result, stderr = run(root_old, before_old, Path(temp) / "old.json", "old")
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None and "no matching" in result["observation_error"], result

        root_invalid = Path(temp) / "invalid-sessions"
        root_invalid.mkdir()
        before_invalid = Path(temp) / "before-invalid.txt"
        before_invalid.write_text("", encoding="utf-8")
        write_session(root_invalid, "invalid", query="invalid")
        code, result, stderr = run(root_invalid, before_invalid, Path(temp) / "invalid.json", "invalid", started="not-a-date")
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None and "started timestamp" in result["observation_error"], result

        # ---- TDD tests for --prompt-file exact matching ----
        # Smoke prompt with fallback instructions
        smoke_prompt_text = (
            "/deep-research-dev:deep-research-dev --ephemeral --unattended smoke-fallback-query\n\n"
            "Before normal synthesis:\n"
            "1. Write the retained-claim and complete source-ledger JSON with all required fields to:\n"
            "/path/to/fallback-input.json\n"
            "2. Run the exact installed plugin fallback builder:\n"
            "python3 \"/path/to/build-fallback-report.py\" \"/path/to/fallback-input.json\" --output \"/path/to/fallback.md\"\n\n"
            "When the research report is complete, print a line exactly:\n"
            "===REPORT===\n"
            "then print the final report only (no tool narration)."
        )
        prompt_file = Path(temp) / "invocation-prompt.txt"
        prompt_file.write_text(smoke_prompt_text, encoding="utf-8")

        # 1. Session with new smoke prompt fails to match legacy reconstruction (--query)
        root_smoke = Path(temp) / "smoke-prompt-sessions"
        root_smoke.mkdir()
        before_smoke = Path(temp) / "before-smoke.txt"
        before_smoke.write_text("", encoding="utf-8")
        write_session(
            root_smoke,
            "smoke-sess",
            query="smoke-fallback-query",
            exact_prompt=smoke_prompt_text,
        )
        code, result, stderr = run(root_smoke, before_smoke, Path(temp) / "legacy-fail.json", query="smoke-fallback-query")
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None and "no matching" in result["observation_error"], result

        # 2. Same session matches when resolve --prompt-file receives exact persisted prompt
        code, result, stderr = run(
            root_smoke,
            before_smoke,
            Path(temp) / "prompt-file-pass.json",
            prompt_file=prompt_file,
        )
        assert code == 0, (code, stderr, result)
        assert result["actual_model"] == "deepseek-v4-flash-max", result
        assert result["session_id"] == "smoke-sess", result

        # 3. One-character / prefix-extended prompt still fails closed
        prompt_file_extended = Path(temp) / "prompt-extended.txt"
        prompt_file_extended.write_text(smoke_prompt_text + "!", encoding="utf-8")
        code, result, stderr = run(
            root_smoke,
            before_smoke,
            Path(temp) / "prompt-extended-fail.json",
            prompt_file=prompt_file_extended,
        )
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None and "no matching" in result["observation_error"], result

        # 4. <user_query> wrapped and split-block exact prompt-file forms still match
        root_wrapped_pf = Path(temp) / "wrapped-pf-sessions"
        root_wrapped_pf.mkdir()
        before_wrapped_pf = Path(temp) / "before-wrapped-pf.txt"
        before_wrapped_pf.write_text("", encoding="utf-8")
        write_session(
            root_wrapped_pf,
            "wrapped-pf",
            query="ignored",
            exact_prompt=smoke_prompt_text,
            wrap_user_query=True,
            split_prompt_blocks=True,
            trailing_whitespace=True,
        )
        code, result, stderr = run(
            root_wrapped_pf,
            before_wrapped_pf,
            Path(temp) / "wrapped-pf-pass.json",
            prompt_file=prompt_file,
        )
        assert code == 0, (code, stderr, result)
        assert result["session_id"] == "wrapped-pf", result

        # 5. Missing / unreadable prompt file fails closed with deterministic observation error
        missing_pf = Path(temp) / "nonexistent-prompt.txt"
        code, result, stderr = run(
            root_smoke,
            before_smoke,
            Path(temp) / "missing-pf.json",
            prompt_file=missing_pf,
        )
        assert code == 1, (code, stderr, result)
        assert result["actual_model"] is None, result
        assert "cannot read prompt file" in result.get("observation_error", "") or "prompt file" in result.get("observation_error", ""), result

        # 6. Both --query and --prompt-file or neither fails closed (or clear CLI error)
        code, result, stderr = run(
            root_smoke,
            before_smoke,
            Path(temp) / "neither.json",
        )
        assert code != 0, (code, stderr, result)

        code, result, stderr = run(
            root_smoke,
            before_smoke,
            Path(temp) / "both.json",
            query="smoke-fallback-query",
            prompt_file=prompt_file,
        )
        assert code != 0, (code, stderr, result)

    print("session provenance: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
