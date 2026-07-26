#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class PlanRow:
    file: str
    path: str
    status: str
    score: int | float | None
    age_days: float | None
    repo: str | None
    pr_number: int | None
    pr_url: str | None
    primary_pr_source: str | None
    github_state: str | None
    github_checked: bool | None
    github_title: str | None
    github_url: str | None
    github_merged_at: str | None
    github_error: str | None
    eligible_for_archive: bool | None
    reasons: list[str]


@dataclass(frozen=True)
class PlanFileInfo:
    title: str | None
    frontmatter: dict[str, str]
    declared_status_line: str | None
    checked_boxes: int
    unchecked_boxes: int
    referenced_paths: list[str]


@dataclass(frozen=True)
class RowAnalysis:
    effective_repo: str | None
    effective_pr: int | None
    plan: PlanFileInfo | None
    repo_dir: Path | None
    repo_ref: str | None
    missing_paths: list[str]
    flags: list[str]


@dataclass(frozen=True)
class RepoTreeIndex:
    files: set[str]
    dirs: set[str]


_PATH_RE = re.compile(
    r"(?<![\w-])((?:apps|packages|crates|scripts)/[A-Za-z0-9_@.$/\\-]+)"
)
_STATUS_LINE_RE = re.compile(r"(?im)^\s*(?:#+\s*)?status\s*:\s*(.+)\s*$")


def _run_claude_planctl_scan(
    limit: int,
    cooldown_days: int,
    min_score: int,
    repo_scope_file: str | None,
    github_check: bool | None,
    fuzzy_match: bool | None,
) -> dict[str, Any]:
    cmd: list[str] = [
        "claude-planctl",
        "scan",
        "--format",
        "json",
        "--limit",
        str(limit),
        "--cooldown-days",
        str(cooldown_days),
        "--min-score",
        str(min_score),
    ]
    if repo_scope_file:
        cmd += ["--repo-scope-file", repo_scope_file]
    if github_check is True:
        cmd += ["--github-check"]
    elif github_check is False:
        cmd += ["--no-github-check"]
    if fuzzy_match is True:
        cmd += ["--fuzzy-match"]
    elif fuzzy_match is False:
        cmd += ["--no-fuzzy-match"]

    try:
        raw = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        out = e.output.decode("utf-8", errors="replace") if e.output else ""
        print("status_review.py: claude-planctl scan failed", file=sys.stderr)
        if out:
            print(out.rstrip(), file=sys.stderr)
        raise SystemExit(e.returncode)

    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as e:
        print(f"status_review.py: failed to parse claude-planctl JSON output: {e}", file=sys.stderr)
        raise SystemExit(2)


def _load_scan_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"status_review.py: scan file not found: {path}", file=sys.stderr)
        raise SystemExit(2)
    except json.JSONDecodeError as e:
        print(f"status_review.py: invalid JSON in {path}: {e}", file=sys.stderr)
        raise SystemExit(2)


def _as_plan_rows(data: dict[str, Any]) -> list[PlanRow]:
    rows: list[PlanRow] = []
    for r in data.get("records", []):
        github = r.get("github") or {}
        rows.append(
            PlanRow(
                file=str(r.get("file") or ""),
                path=str(r.get("path") or ""),
                status=str(r.get("status") or ""),
                score=r.get("score"),
                age_days=r.get("ageDays"),
                repo=r.get("repo"),
                pr_number=r.get("prNumber"),
                pr_url=r.get("prUrl"),
                primary_pr_source=r.get("primaryPrSource"),
                github_state=github.get("state"),
                github_checked=github.get("checked"),
                github_title=github.get("title"),
                github_url=github.get("url"),
                github_merged_at=github.get("merged_at"),
                github_error=github.get("error"),
                eligible_for_archive=r.get("eligibleForArchive"),
                reasons=list(r.get("reasons") or []),
            )
        )
    return rows


def _fmt_age(age_days: float | None) -> str:
    if age_days is None:
        return "-"
    return f"{age_days:.1f}d"


def _fmt_pr(repo: str | None, pr_number: int | None, pr_url: str | None) -> str:
    if repo and pr_number:
        return f"{repo}#{pr_number}"
    if repo:
        return repo
    if pr_url:
        return pr_url
    return "-"


def _fmt_reasons(reasons: list[str]) -> str:
    if not reasons:
        return "-"
    return ", ".join(f"`{r}`" for r in reasons)


def _fmt_remaining(remaining_days: float) -> str:
    if remaining_days <= 0:
        return "0h"
    if remaining_days < 1:
        return f"{remaining_days * 24:.1f}h"
    return f"{remaining_days:.1f}d"


def _parse_iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    v = value.strip()
    if not v:
        return None
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(v)
    except ValueError:
        return None
    if dt.tzinfo is None:
        return None
    return dt


def _is_resolved_repo(repo: str | None) -> bool:
    if not repo:
        return False
    if repo.strip() in {"-", "owner/repo"}:
        return False
    return "/" in repo


def _parse_simple_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """
    Parse simple YAML frontmatter.
    - Accepts only key: value pairs (strings).
    - Returns (frontmatter_dict, body_text_without_frontmatter).
    """
    if not text.startswith("---\n"):
        return {}, text

    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text

    end_idx = None
    for i in range(1, min(len(lines), 200)):
        if lines[i].strip() == "---":
            end_idx = i
            break

    if end_idx is None:
        return {}, text

    fm: dict[str, str] = {}
    for raw in lines[1:end_idx]:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            fm[key] = value

    body = "\n".join(lines[end_idx + 1 :]).lstrip("\n")
    return fm, body


def _extract_plan_title(body: str) -> str | None:
    for line in body.splitlines()[:80]:
        m = re.match(r"^\s*#\s+(.+?)\s*$", line)
        if m:
            return m.group(1).strip()
    return None


def _extract_declared_status_line(body: str) -> str | None:
    for line in body.splitlines()[:80]:
        m = _STATUS_LINE_RE.match(line)
        if m:
            return f"Status: {m.group(1).strip()}"
        m2 = re.match(r"^\s*\*\*status\*\*\s*:\s*(.+?)\s*$", line, flags=re.IGNORECASE)
        if m2:
            return f"Status: {m2.group(1).strip()}"
    return None


def _classify_declared_status(line: str | None) -> str | None:
    if not line:
        return None
    normalized = line.lower()
    if "no action required" in normalized:
        return "no_action"
    if "to be implemented" in normalized or "tbd" in normalized or "todo" in normalized:
        return "todo"
    if "implemented" in normalized or "deployed" in normalized:
        return "implemented"
    if "in progress" in normalized:
        return "in_progress"
    return None


def _extract_referenced_paths(text: str) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for m in _PATH_RE.finditer(text):
        raw = m.group(1)
        cleaned = raw.strip().strip("`").rstrip(").,:;\"'")
        cleaned = cleaned.replace("\\", "/")
        if cleaned and cleaned not in seen:
            seen.add(cleaned)
            out.append(cleaned)
    return out


def _count_checkboxes(text: str) -> tuple[int, int]:
    checked = len(re.findall(r"(?i)\[[x]\]", text))
    unchecked = len(re.findall(r"(?i)\[\s\]", text))
    return checked, unchecked


def _parse_int(value: str | None) -> int | None:
    if value is None:
        return None
    s = value.strip()
    if not s:
        return None
    if not re.fullmatch(r"[0-9]+", s):
        return None
    try:
        return int(s, 10)
    except ValueError:
        return None


class Analyzer:
    def __init__(
        self,
        *,
        repo_root: Path,
        repo_dir_overrides: dict[str, Path],
        repo_candidates: list[str],
        git_fetch: bool,
    ) -> None:
        self._repo_root = repo_root
        self._repo_dir_overrides = repo_dir_overrides
        self._repo_candidates = [r for r in repo_candidates if _is_resolved_repo(r)]
        self._git_fetch = git_fetch

        self._plan_cache: dict[str, PlanFileInfo | None] = {}
        self._repo_dir_cache: dict[str, Path | None] = {}
        self._repo_ref_cache: dict[str, str | None] = {}
        self._repo_tree_cache: dict[tuple[str, str], RepoTreeIndex | None] = {}
        self._repo_fetched: set[str] = set()

    def get_plan_info(self, plan_path: str) -> PlanFileInfo | None:
        if plan_path in self._plan_cache:
            return self._plan_cache[plan_path]

        path = Path(plan_path)
        try:
            text = path.read_text(encoding="utf-8")
        except Exception:
            self._plan_cache[plan_path] = None
            return None

        frontmatter, body = _parse_simple_frontmatter(text)
        title = _extract_plan_title(body)
        declared_status_line = _extract_declared_status_line(body)
        checked, unchecked = _count_checkboxes(text)
        referenced_paths = _extract_referenced_paths(text)

        info = PlanFileInfo(
            title=title,
            frontmatter=frontmatter,
            declared_status_line=declared_status_line,
            checked_boxes=checked,
            unchecked_boxes=unchecked,
            referenced_paths=referenced_paths,
        )
        self._plan_cache[plan_path] = info
        return info

    def resolve_repo_dir(self, repo: str) -> Path | None:
        if repo in self._repo_dir_cache:
            return self._repo_dir_cache[repo]

        if repo in self._repo_dir_overrides:
            resolved = self._repo_dir_overrides[repo]
            self._repo_dir_cache[repo] = resolved if resolved.exists() else None
            return self._repo_dir_cache[repo]

        repo_name = repo.split("/")[-1]
        candidate = (self._repo_root / repo_name).expanduser()
        if candidate.exists():
            self._repo_dir_cache[repo] = candidate
            return candidate

        self._repo_dir_cache[repo] = None
        return None

    def _git(self, repo_dir: Path, args: list[str]) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            ["git", "-C", str(repo_dir), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def ensure_fetched(self, repo_dir: Path) -> None:
        key = str(repo_dir)
        if not self._git_fetch or key in self._repo_fetched:
            return
        self._repo_fetched.add(key)
        _ = self._git(repo_dir, ["fetch", "--all", "--prune"])

    def get_origin_default_ref(self, repo_dir: Path) -> str | None:
        key = str(repo_dir)
        if key in self._repo_ref_cache:
            return self._repo_ref_cache[key]

        self.ensure_fetched(repo_dir)
        proc = self._git(repo_dir, ["symbolic-ref", "refs/remotes/origin/HEAD"])
        if proc.returncode == 0:
            ref = proc.stdout.decode("utf-8", errors="replace").strip()
            ref = ref.removeprefix("refs/remotes/").strip()
            self._repo_ref_cache[key] = ref
            return ref

        # Fallbacks
        for candidate in ["origin/main", "origin/master"]:
            ok = self._git(repo_dir, ["rev-parse", "--verify", "--quiet", candidate]).returncode == 0
            if ok:
                self._repo_ref_cache[key] = candidate
                return candidate

        self._repo_ref_cache[key] = None
        return None

    def get_repo_tree_index(self, repo_dir: Path, ref: str) -> RepoTreeIndex | None:
        cache_key = (str(repo_dir), ref)
        if cache_key in self._repo_tree_cache:
            return self._repo_tree_cache[cache_key]

        self.ensure_fetched(repo_dir)
        proc = self._git(repo_dir, ["ls-tree", "-r", "--name-only", ref])
        if proc.returncode != 0:
            self._repo_tree_cache[cache_key] = None
            return None

        files = set(
            line.strip()
            for line in proc.stdout.decode("utf-8", errors="replace").splitlines()
            if line.strip()
        )
        dirs: set[str] = set()
        for file_path in files:
            prefix = ""
            for part in file_path.split("/")[:-1]:
                prefix += f"{part}/"
                dirs.add(prefix)

        index = RepoTreeIndex(files=files, dirs=dirs)
        self._repo_tree_cache[cache_key] = index
        return index

    def analyze_row(self, row: PlanRow) -> RowAnalysis:
        plan = self.get_plan_info(row.path)

        fm_repo = plan.frontmatter.get("repo") if plan else None
        effective_repo = row.repo if _is_resolved_repo(row.repo) else (fm_repo if _is_resolved_repo(fm_repo) else None)

        fm_pr = _parse_int(plan.frontmatter.get("pr")) if plan else None
        effective_pr = row.pr_number if row.pr_number else fm_pr

        inferred_repo: str | None = None
        if not effective_repo and plan and plan.referenced_paths:
            inferred_repo = self.infer_repo_from_paths(plan.referenced_paths)
            if inferred_repo:
                effective_repo = inferred_repo

        repo_dir = self.resolve_repo_dir(effective_repo) if effective_repo else None
        repo_ref = self.get_origin_default_ref(repo_dir) if repo_dir else None

        missing_paths: list[str] = []
        if repo_dir and repo_ref and plan and plan.referenced_paths:
            index = self.get_repo_tree_index(repo_dir, repo_ref)
            if index is not None:
                for p in plan.referenced_paths:
                    if p in index.files:
                        continue
                    dir_key = p.rstrip("/") + "/"
                    if dir_key in index.dirs:
                        continue
                    missing_paths.append(p)

        flags: list[str] = []
        if not effective_repo:
            flags.append("missing_repo")
        elif not repo_dir:
            flags.append("repo_not_found_locally")
        if inferred_repo:
            flags.append("inferred_repo")
        if row.primary_pr_source == "semantic_override":
            flags.append("semantic_pr_match")
        if row.github_error:
            flags.append("github_error")
        if plan and missing_paths:
            flags.append("stale_paths")
        if plan:
            declared_kind = _classify_declared_status(plan.declared_status_line)
            if declared_kind == "todo":
                flags.append("plan_declares_todo")
            elif declared_kind == "implemented":
                flags.append("plan_declares_implemented")
            fm_status = (plan.frontmatter.get("status") or "").strip()
            if fm_status and fm_status != row.status:
                flags.append("status_mismatch")
        if plan and (plan.unchecked_boxes > 0):
            flags.append("unchecked_boxes")

        return RowAnalysis(
            effective_repo=effective_repo,
            effective_pr=effective_pr,
            plan=plan,
            repo_dir=repo_dir,
            repo_ref=repo_ref,
            missing_paths=missing_paths,
            flags=flags,
        )

    def infer_repo_from_paths(self, referenced_paths: list[str]) -> str | None:
        """
        Infer repo by checking which known repo candidates contain all referenced paths.
        Conservative: return a repo only if exactly one candidate has 0 missing paths.
        """
        if not referenced_paths:
            return None

        best: list[tuple[str, int]] = []
        for repo in self._repo_candidates:
            repo_dir = self.resolve_repo_dir(repo)
            if not repo_dir:
                continue
            repo_ref = self.get_origin_default_ref(repo_dir)
            if not repo_ref:
                continue
            index = self.get_repo_tree_index(repo_dir, repo_ref)
            if not index:
                continue
            missing = 0
            for p in referenced_paths:
                if p in index.files:
                    continue
                dir_key = p.rstrip("/") + "/"
                if dir_key in index.dirs:
                    continue
                missing += 1
            best.append((repo, missing))

        zero = [repo for repo, missing in best if missing == 0]
        if len(zero) == 1:
            return zero[0]
        return None


def _render_frontmatter_summary(plan: PlanFileInfo | None) -> str | None:
    if not plan or not plan.frontmatter:
        return None
    keys = ["repo", "status", "pr", "updated", "owner"]
    parts: list[str] = []
    for k in keys:
        v = (plan.frontmatter.get(k) or "").strip()
        if v:
            parts.append(f"{k}={v}")
    return ", ".join(parts) if parts else None


def _suggest_frontmatter_status(row: PlanRow, analysis: RowAnalysis) -> str | None:
    """
    Suggest a stable, human-owned plan status for YAML frontmatter.

    Note: this is intentionally NOT the same as the planctl bucket.
    """
    plan = analysis.plan
    declared_kind = _classify_declared_status(plan.declared_status_line) if plan else None
    if declared_kind == "implemented":
        return "implemented"
    if row.status == "archive_candidate":
        return "implemented"
    if row.status == "follow_up":
        return "follow_up"
    if row.status == "active":
        return "active"
    return None


def _format_frontmatter_hint(row: PlanRow, analysis: RowAnalysis) -> str:
    repo = analysis.effective_repo
    pr = analysis.effective_pr
    status = _suggest_frontmatter_status(row, analysis)
    owner = os.environ.get("USER") or "owner"

    parts: list[str] = []
    if repo:
        parts.append(f"repo={repo}")
    if pr:
        parts.append(f"pr={pr}")
    if status:
        parts.append(f"status={status}")
    parts.append("updated=YYYY-MM-DD")
    parts.append(f"owner={owner}")
    return ", ".join(parts)


def _render_frontmatter_fixups(
    *,
    rows: list[PlanRow],
    max_items: int,
    analyzer: Analyzer,
) -> str | None:
    """
    Render copy-paste YAML frontmatter suggestions for plans that are currently unstable
    due to missing repo/PR metadata (common cause of `pr_without_repo` / `missing_repo`).
    """
    if max_items <= 0 or not rows:
        return None

    today = datetime.now().astimezone().date().isoformat()
    default_owner = (os.environ.get("USER") or "").strip()

    candidates: list[tuple[int, PlanRow, RowAnalysis, dict[str, str], list[str]]] = []
    for row in rows:
        analysis = analyzer.analyze_row(row)
        plan = analysis.plan
        if not plan:
            continue

        suggested: dict[str, str] = {}
        notes: list[str] = []

        fm_repo = (plan.frontmatter.get("repo") or "").strip()
        if (not _is_resolved_repo(fm_repo)) and _is_resolved_repo(analysis.effective_repo):
            suggested["repo"] = analysis.effective_repo or ""
            if "inferred_repo" in analysis.flags:
                notes.append("repo inferred from referenced paths")

        fm_pr = _parse_int(plan.frontmatter.get("pr"))
        if fm_pr is None and analysis.effective_pr and _is_resolved_repo(analysis.effective_repo):
            suggested["pr"] = str(analysis.effective_pr)

        fm_status = (plan.frontmatter.get("status") or "").strip()
        suggested_status = _suggest_frontmatter_status(row, analysis)
        if suggested_status and (not fm_status or fm_status != suggested_status):
            # Only auto-suggest status when we have a strong signal (declared implemented) or a non-review_needed bucket.
            if "plan_declares_implemented" in analysis.flags or row.status in {"active", "follow_up", "archive_candidate"}:
                suggested["status"] = suggested_status
                if "plan_declares_implemented" in analysis.flags:
                    notes.append("plan declares implemented")

        # Only suggest updated/owner when we are already suggesting something meaningful.
        if suggested:
            if not (plan.frontmatter.get("updated") or "").strip():
                suggested["updated"] = today
            if not (plan.frontmatter.get("owner") or "").strip() and default_owner:
                suggested["owner"] = default_owner

        # Ignore trivial fixups (avoid churn): require at least repo/pr/status.
        if not any(k in suggested for k in ("repo", "pr", "status")):
            continue

        priority = 0
        if "repo" in suggested:
            priority += 100
        if "pr" in suggested:
            priority += 50
        if "status" in suggested:
            priority += 25
        if row.status == "review_needed":
            priority += 10
        candidates.append((priority, row, analysis, suggested, notes))

    if not candidates:
        return None

    candidates.sort(key=lambda t: (-t[0], t[1].file.lower()))
    selected = candidates[:max_items]

    out: list[str] = [
        "## Frontmatter Fixups (Copy-Paste)",
        "",
        "These suggestions reduce `pr_without_repo` / `missing_repo` churn in plan scans.",
        "If a plan already has YAML frontmatter, merge the keys (do not add a second `---` block).",
        "",
    ]

    for _, row, analysis, suggested, notes in selected:
        out.append(f"`{row.file}` — `{row.path}`")
        if notes:
            out.append(f"Notes: {', '.join(notes)}")
        out.append("")
        plan_has_frontmatter = bool(analysis.plan and analysis.plan.frontmatter)
        if not plan_has_frontmatter:
            out.append("```yaml")
            out.append("---")
            for k, v in suggested.items():
                out.append(f"{k}: {v}")
            out.append("---")
            out.append("```")
        else:
            out.append("```yaml")
            for k, v in suggested.items():
                out.append(f"{k}: {v}")
            out.append("```")
        out.append("")

    return "\n".join(out)


def _suggest_action(row: PlanRow, analysis: RowAnalysis) -> str:
    gh_state = (row.github_state or "").upper()
    declared_kind = _classify_declared_status(analysis.plan.declared_status_line) if analysis.plan else None

    if "stale_paths" in analysis.flags:
        return "Revise plan: referenced file paths do not match current codebase."

    if gh_state == "CLOSED" and row.github_merged_at is None:
        if analysis.plan and analysis.plan.referenced_paths and not analysis.missing_paths:
            return "PR is closed (not merged) and plan paths look valid: decide follow-up/new PR; if work landed elsewhere, update the linked PR."
        return "PR is closed (not merged): decide follow-up/new PR or mark obsolete; update plan status."

    if gh_state == "MERGED":
        if declared_kind == "todo" or "unchecked_boxes" in analysis.flags:
            return "PR is merged but plan still indicates remaining work: keep follow_up and list what’s left (or split plan)."
        if row.status == "archive_candidate" and row.eligible_for_archive:
            return "Ready to archive: run `claude-planctl archive --dry-run --cooldown-days 7 --min-score 85`."
        if row.status == "follow_up":
            return "PR is merged but plan is follow_up: verify if anything remains; then set implemented or keep follow_up with remaining tasks."
        return "PR is merged: verify in codebase, then set implemented; archive only after cooldown and dry-run review."

    if "inferred_repo" in analysis.flags and analysis.effective_repo:
        return f"Add YAML frontmatter: {_format_frontmatter_hint(row, analysis)} (repo inferred from referenced paths)."

    if not analysis.effective_repo:
        owner = os.environ.get("USER") or "owner"
        return f"Add YAML frontmatter `repo: owner/repo` (required), plus optional `pr`, `status`, `updated`, `owner: {owner}`; then re-run scan."

    if row.status == "review_needed":
        return "Manual triage required: confirm correct repo/PR and update plan metadata/status."

    return "Review and update metadata/status; capture blockers explicitly if follow_up."


def _render_section(
    title: str,
    rows: list[PlanRow],
    max_items: int,
    *,
    analyzer: Analyzer,
    max_paths: int,
    cooldown_days: int,
) -> str:
    now = datetime.now().astimezone()
    out: list[str] = [f"## {title}", ""]
    if not rows:
        out.append("_None._")
        out.append("")
        return "\n".join(out)

    for row in rows[:max_items]:
        analysis = analyzer.analyze_row(row)
        pr = _fmt_pr(analysis.effective_repo, analysis.effective_pr, row.pr_url)
        gh = row.github_state or "-"
        src = row.primary_pr_source or "-"
        score = "-" if row.score is None else str(row.score)
        fm_summary = _render_frontmatter_summary(analysis.plan)
        plan_title = analysis.plan.title if analysis.plan else None

        out.append(
            f"- `{row.file}` (planctl: {row.status}, age {_fmt_age(row.age_days)}, score {score}) — {pr} (gh: {gh}, source: {src})"
        )
        out.append(f"  - Path: `{row.path}`")
        if plan_title:
            out.append(f"  - Title: {plan_title}")
        if fm_summary:
            out.append(f"  - Frontmatter: {fm_summary}")
        reasons = [r for r in row.reasons if r != "gate:status_not_archive_candidate"]
        if reasons:
            out.append(f"  - Planctl reasons: {_fmt_reasons(reasons)}")
        if row.status == "archive_candidate" and row.eligible_for_archive is not None:
            eligible = "yes" if row.eligible_for_archive else "no"
            out.append(f"  - Archive eligible: {eligible}")
            if (
                not row.eligible_for_archive
                and "gate:cooldown_not_met" in row.reasons
            ):
                merged_at = _parse_iso_datetime(row.github_merged_at)
                if merged_at is not None:
                    elapsed_days = (now - merged_at).total_seconds() / 86400.0
                    remaining = float(cooldown_days) - elapsed_days
                    if remaining > 0:
                        out.append(f"  - Cooldown remaining: {_fmt_remaining(remaining)} (gate={cooldown_days}d)")
        if analysis.plan and analysis.plan.declared_status_line:
            out.append(f"  - Declared: {analysis.plan.declared_status_line}")
        if analysis.plan and (analysis.plan.checked_boxes or analysis.plan.unchecked_boxes):
            out.append(
                f"  - Checkboxes: {analysis.plan.unchecked_boxes} open / {analysis.plan.checked_boxes} done"
            )
        if analysis.effective_repo and analysis.repo_dir and analysis.repo_ref:
            total_refs = len(analysis.plan.referenced_paths) if analysis.plan else 0
            missing = len(analysis.missing_paths)
            out.append(
                f"  - Codebase: `{analysis.repo_dir}` @ `{analysis.repo_ref}` (refs {total_refs}, missing {missing})"
            )
            if analysis.missing_paths:
                shown = analysis.missing_paths[:max_paths]
                shown_fmt = ", ".join(f"`{p}`" for p in shown)
                suffix = f" (+{len(analysis.missing_paths) - len(shown)} more)" if len(analysis.missing_paths) > len(shown) else ""
                out.append(f"  - Missing paths: {shown_fmt}{suffix}")
        elif analysis.effective_repo and not analysis.repo_dir:
            out.append(f"  - Codebase: local checkout not found for `{analysis.effective_repo}`")
        out.append(f"  - Suggested: {_suggest_action(row, analysis)}")
        if analysis.flags:
            out.append(f"  - Flags: {', '.join(analysis.flags)}")
    if len(rows) > max_items:
        out.append(f"- _…and {len(rows) - max_items} more._")
    out.append("")
    return "\n".join(out)


def _extract_index_keywords(plan: PlanFileInfo | None, max_keywords: int) -> list[str]:
    if not plan or not plan.referenced_paths or max_keywords <= 0:
        return []

    tokens: set[str] = set()
    for p in plan.referenced_paths:
        parts = p.split("/")
        if len(parts) < 2:
            continue
        token = parts[1].strip()
        if not token:
            continue
        tokens.add(token)

    return sorted(tokens, key=lambda s: s.lower())[:max_keywords]


def _render_plan_index(
    *,
    by_status: dict[str, list[PlanRow]],
    analyzer: Analyzer,
    max_keywords: int,
) -> str:
    """
    Render a lightweight, search-friendly index of ALL plans (not truncated).

    Motivation: the detailed sections are intentionally capped by --max-items, but users
    still need a "topic search" surface (e.g. search `cmux-devbox` to find a plan file).
    """
    out: list[str] = [
        "## Plan Index (Search by Keyword)",
        "",
        "Search this section for topic keywords (matches plan titles + extracted path tokens).",
        "",
    ]

    status_order = ["active", "follow_up", "review_needed", "archive_candidate"]
    for status in status_order:
        rows = list(by_status.get(status) or [])
        if not rows:
            continue

        # Sort alphabetically by title to make manual scanning a bit easier.
        def sort_key(row: PlanRow) -> tuple[str, str]:
            plan = analyzer.get_plan_info(row.path)
            title = (plan.title if plan and plan.title else "").strip()
            return (title.lower(), row.file.lower())

        rows.sort(key=sort_key)

        out.append(f"### {status}")
        out.append("")

        for row in rows:
            plan = analyzer.get_plan_info(row.path)
            title = (plan.title if plan and plan.title else None) or row.github_title or ""
            title_repr = json.dumps(title, ensure_ascii=False) if title else '""'
            keywords = _extract_index_keywords(plan, max_keywords=max_keywords)
            kw = f", keywords=`{', '.join(keywords)}`" if keywords else ""
            out.append(f"- `{row.file}`: title={title_repr}, path=`{row.path}`{kw}")

        out.append("")

    return "\n".join(out)


def _write_report(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate a prioritized review queue for active/follow_up plans.")
    parser.add_argument("--out", default="~/.claude/plans/PLAN_STATUS_REVIEW.md", help="Output markdown path.")
    parser.add_argument("--scan", help="Optional claude-planctl scan JSON file; if omitted, run claude-planctl.")
    parser.add_argument("--limit", type=int, default=500, help="Plan scan record limit.")
    parser.add_argument("--cooldown-days", type=int, default=7, help="Cooldown days (match archive safety gate).")
    parser.add_argument("--min-score", type=int, default=85, help="Minimum score (match archive safety gate).")
    parser.add_argument(
        "--repo-scope-file",
        default="~/.claude/plans/planctl.json",
        help="planctl config JSON path (repo scope + fuzzy settings).",
    )
    parser.add_argument("--no-repo-scope-file", action="store_true", help="Do not pass --repo-scope-file to planctl.")
    parser.add_argument("--github-check", dest="github_check", action="store_true")
    parser.add_argument("--no-github-check", dest="github_check", action="store_false")
    parser.add_argument("--fuzzy-match", dest="fuzzy_match", action="store_true", default=None)
    parser.add_argument("--no-fuzzy-match", dest="fuzzy_match", action="store_false", default=None)
    parser.add_argument("--max-items", type=int, default=20, help="Max items per section.")
    parser.add_argument("--max-paths", type=int, default=6, help="Max missing paths to print per plan.")
    parser.add_argument(
        "--max-fixups",
        type=int,
        default=15,
        help="Max frontmatter fixups to print (copy-paste suggestions).",
    )
    parser.add_argument(
        "--index-max-keywords",
        type=int,
        default=6,
        help="Max extracted path tokens (e.g. packages/<token>) to include per plan in the Plan Index.",
    )
    parser.add_argument("--repo-root", default="~/Desktop/code", help="Root directory containing local repo checkouts.")
    parser.add_argument(
        "--repo-dir",
        action="append",
        default=[],
        help="Override repo dir mapping: owner/repo=/abs/path (repeatable).",
    )
    parser.add_argument("--git-fetch", dest="git_fetch", action="store_true")
    parser.add_argument("--no-git-fetch", dest="git_fetch", action="store_false")
    parser.set_defaults(github_check=True, git_fetch=True)
    args = parser.parse_args(argv)

    out_path = Path(os.path.expanduser(args.out)).resolve()
    repo_scope_file = None if args.no_repo_scope_file else os.path.expanduser(args.repo_scope_file)

    repo_dir_overrides: dict[str, Path] = {}
    for entry in args.repo_dir:
        if "=" not in entry:
            continue
        repo, raw_path = entry.split("=", 1)
        repo = repo.strip()
        raw_path = raw_path.strip()
        if repo and raw_path:
            repo_dir_overrides[repo] = Path(os.path.expanduser(raw_path)).resolve()

    if args.scan:
        data = _load_scan_json(Path(os.path.expanduser(args.scan)).resolve())
    else:
        data = _run_claude_planctl_scan(
            limit=args.limit,
            cooldown_days=args.cooldown_days,
            min_score=args.min_score,
            repo_scope_file=repo_scope_file,
            github_check=args.github_check,
            fuzzy_match=args.fuzzy_match,
        )

    settings = data.get("settings") or {}
    repo_candidates = settings.get("repoScope") or []
    if not isinstance(repo_candidates, list):
        repo_candidates = []

    analyzer = Analyzer(
        repo_root=Path(os.path.expanduser(args.repo_root)).resolve(),
        repo_dir_overrides=repo_dir_overrides,
        repo_candidates=[str(r) for r in repo_candidates],
        git_fetch=bool(args.git_fetch),
    )

    rows = _as_plan_rows(data)

    by_status: dict[str, list[PlanRow]] = {
        "review_needed": [],
        "active": [],
        "follow_up": [],
        "archive_candidate": [],
    }
    for row in rows:
        if row.status in by_status:
            by_status[row.status].append(row)

    for key in by_status:
        by_status[key].sort(key=lambda r: (r.age_days or -1.0), reverse=True)

    now = datetime.now().astimezone().isoformat(timespec="seconds")
    tool_version = data.get("toolVersion") or "-"
    generated_at = data.get("generatedAt") or "-"

    summary = data.get("summary") or {}
    totals_line = ", ".join(
        f"{k}={summary.get(k, 0)}"
        for k in ["review_needed", "active", "follow_up", "archive_candidate"]
        if k in summary
    )

    merged_open = sum(
        1
        for r in rows
        if (r.github_state or "").upper() == "MERGED" and r.status in {"active", "follow_up", "review_needed"}
    )
    closed_unmerged = sum(
        1
        for r in rows
        if (r.github_state or "").upper() == "CLOSED" and not r.github_merged_at and r.status != "archive_candidate"
    )
    eligible = sum(1 for r in rows if r.eligible_for_archive)

    content_parts = [
        "# Plan Status Review",
        "",
        f"- Generated: `{now}`",
        f"- claude-planctl: `{tool_version}` (scan generatedAt: `{generated_at}`)",
        f"- Gates: cooldownDays=`{args.cooldown_days}`, minScore=`{args.min_score}`",
        f"- Totals: {totals_line}" if totals_line else None,
        f"- Signals: merged-but-still-open=`{merged_open}`, closed-unmerged=`{closed_unmerged}`, eligibleForArchive=`{eligible}`",
        "",
        "This report is advisory. Update plan files manually; archive only after `claude-planctl archive --dry-run` review.",
        "",
        _render_frontmatter_fixups(
            rows=by_status["review_needed"],
            max_items=int(args.max_fixups),
            analyzer=analyzer,
        ),
        _render_plan_index(by_status=by_status, analyzer=analyzer, max_keywords=int(args.index_max_keywords)),
        _render_section(
            "Review Needed",
            by_status["review_needed"],
            args.max_items,
            analyzer=analyzer,
            max_paths=args.max_paths,
            cooldown_days=args.cooldown_days,
        ),
        _render_section(
            "Active (Oldest First)",
            by_status["active"],
            args.max_items,
            analyzer=analyzer,
            max_paths=args.max_paths,
            cooldown_days=args.cooldown_days,
        ),
        _render_section(
            "Follow Up (Oldest First)",
            by_status["follow_up"],
            args.max_items,
            analyzer=analyzer,
            max_paths=args.max_paths,
            cooldown_days=args.cooldown_days,
        ),
        _render_section(
            "Archive Candidates",
            by_status["archive_candidate"],
            args.max_items,
            analyzer=analyzer,
            max_paths=args.max_paths,
            cooldown_days=args.cooldown_days,
        ),
    ]

    cleaned_parts = [p for p in content_parts if p is not None]
    _write_report(out_path, "\n".join(cleaned_parts).rstrip() + "\n")
    print(f"Wrote report: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
