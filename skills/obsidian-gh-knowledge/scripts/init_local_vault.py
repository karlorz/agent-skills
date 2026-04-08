#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse


CONFIG_PATH = Path("~/.config/obsidian-gh-knowledge/config.json").expanduser()


def _expand_path(path: str) -> str:
    return os.path.abspath(os.path.expanduser(os.path.expandvars(path)))


def _display_path(path: str) -> str:
    home = str(Path.home())
    normalized = os.path.abspath(path)
    if normalized == home:
        return "~"
    if normalized.startswith(home + os.sep):
        return "~/" + os.path.relpath(normalized, home)
    return normalized


def _die(message: str, exit_code: int = 2) -> None:
    print(message, file=sys.stderr)
    sys.exit(exit_code)


def _run(cmd: list[str], *, cwd: str | None = None) -> None:
    try:
        subprocess.run(cmd, cwd=cwd, capture_output=True, check=True, text=True)
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        details = "\n".join(part for part in [stdout, stderr] if part)
        message = f"Command failed ({exc.returncode}): {' '.join(cmd)}"
        if details:
            message = f"{message}\n{details}"
        _die(message, exit_code=exc.returncode)


def _run_no_fail(cmd: list[str], *, cwd: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def _run_capture(cmd: list[str], *, cwd: str) -> str:
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, check=True, text=True)
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        details = "\n".join(part for part in [stdout, stderr] if part)
        message = f"Command failed ({exc.returncode}): {' '.join(cmd)}"
        if details:
            message = f"{message}\n{details}"
        _die(message, exit_code=exc.returncode)
    return result.stdout.strip()


def _repo_file(vault_dir: str, relative_path: str) -> str:
    return os.path.join(vault_dir, *relative_path.split("/"))


def _config_get(vault_dir: str, *args: str) -> str:
    try:
        return _run_capture(["git", "config", *args], cwd=vault_dir)
    except SystemExit:
        return ""


def _parse_repo_url(repo_url: str) -> tuple[str, str]:
    candidate = repo_url.strip()
    if not candidate:
        _die("Missing repo URL.")

    if candidate.startswith("git@github.com:"):
        path = candidate.split(":", 1)[1]
    elif "://" in candidate:
        parsed = urlparse(candidate)
        if parsed.netloc.lower() != "github.com":
            _die(f"Only github.com repo URLs are supported for bootstrap: {repo_url}")
        path = parsed.path
    else:
        path = candidate

    path = path.strip().strip("/")
    if path.endswith(".git"):
        path = path[:-4]

    parts = [part for part in path.split("/") if part]
    if len(parts) != 2:
        _die(
            "Repo must be in one of these forms: https://github.com/<owner>/<repo>, "
            "git@github.com:<owner>/<repo>.git, or <owner>/<repo>."
        )
    return parts[0], parts[1]


def _clone_url(owner: str, repo: str, original: str) -> str:
    if "://" in original or original.startswith("git@github.com:"):
        return original
    return f"https://github.com/{owner}/{repo}.git"


def _relative_submodule_path(path: str) -> str:
    candidate = path.strip().replace("\\", "/").strip("/")
    if not candidate:
        _die("Raw submodule path cannot be empty.")
    parts = [part for part in candidate.split("/") if part]
    if not parts or any(part in {".", ".."} for part in parts):
        _die(f"Raw submodule path must be a simple vault-relative path: {path!r}")
    return "/".join(parts)


def _load_config() -> dict:
    if not CONFIG_PATH.exists():
        return {}
    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        _die(f"Failed to read config: {CONFIG_PATH}\n{exc}")
    if not isinstance(data, dict):
        _die(f"Config must contain a JSON object: {CONFIG_PATH}")
    return data


def _write_config(config: dict, *, dry_run: bool) -> None:
    if dry_run:
        return
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with CONFIG_PATH.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")


def _origin_matches(vault_dir: str, repo_slug: str) -> bool:
    git_dir = os.path.join(vault_dir, ".git")
    if not os.path.isdir(git_dir):
        return False
    origin = _run_capture(["git", "config", "--get", "remote.origin.url"], cwd=vault_dir)
    try:
        owner, repo = _parse_repo_url(origin)
    except SystemExit:
        return False
    return f"{owner.lower()}/{repo.lower()}" == repo_slug.lower()


def _ensure_clone(repo_url: str, repo_slug: str, vault_dir: str, *, dry_run: bool) -> str:
    if os.path.exists(vault_dir) and not os.path.isdir(vault_dir):
        _die(f"Vault path exists but is not a directory: {vault_dir}")

    if os.path.isdir(vault_dir):
        entries = os.listdir(vault_dir)
        if entries:
            if _origin_matches(vault_dir, repo_slug):
                return "reuse"
            _die(
                "Vault directory already exists and is not an empty clone of the confirmed repo:\n"
                f"  {vault_dir}\n"
                "Choose another --vault-dir or clean the directory first."
            )
        if dry_run:
            return "clone"
    else:
        if dry_run:
            return "clone"
        os.makedirs(os.path.dirname(vault_dir), exist_ok=True)

    if shutil.which("git") is None:
        _die("git is required for bootstrap but was not found in PATH.")

    if dry_run:
        return "clone"

    _run(["git", "clone", repo_url, vault_dir])
    return "clone"


def _submodule_origin(vault_dir: str, submodule_path: str) -> str | None:
    try:
        origin = _run_capture(
            ["git", "config", "--file", ".gitmodules", "--get", f"submodule.{submodule_path}.url"],
            cwd=vault_dir,
        )
    except SystemExit:
        return None
    return origin or None


def _submodule_matches(vault_dir: str, *, submodule_path: str, repo_slug: str) -> bool:
    configured = _submodule_origin(vault_dir, submodule_path)
    if not configured:
        return False
    try:
        owner, repo = _parse_repo_url(configured)
    except SystemExit:
        return False
    if f"{owner.lower()}/{repo.lower()}" != repo_slug.lower():
        return False

    abs_submodule = os.path.join(vault_dir, submodule_path)
    git_dir = os.path.join(abs_submodule, ".git")
    return os.path.exists(abs_submodule) and os.path.exists(git_dir)


def _submodule_branch(vault_dir: str, submodule_path: str) -> str:
    branch = _config_get(vault_dir, "--file", ".gitmodules", "--get", f"submodule.{submodule_path}.branch")
    return branch or "main"


def _bootstrap_repo_git(vault_dir: str, *, dry_run: bool) -> list[str]:
    actions = [
        "enable worktree config",
        "set worktree-local push.recurseSubmodules=on-demand",
    ]
    if os.path.exists(_repo_file(vault_dir, "scripts/bootstrap-git-hooks.sh")):
        actions.append("repo hook bootstrap available at scripts/bootstrap-git-hooks.sh")

    if dry_run:
        return actions

    _run(["git", "config", "extensions.worktreeConfig", "true"], cwd=vault_dir)
    _run_no_fail(["git", "config", "--local", "--unset-all", "push.recurseSubmodules"], cwd=vault_dir)
    _run(["git", "config", "--worktree", "push.recurseSubmodules", "on-demand"], cwd=vault_dir)
    return actions


def _bootstrap_existing_raw_submodule(vault_dir: str, *, raw_submodule_path: str, dry_run: bool) -> tuple[list[str], str | None]:
    if not os.path.isdir(vault_dir):
        return [], None

    configured_origin = _submodule_origin(vault_dir, raw_submodule_path)
    if not configured_origin:
        return [], None

    branch = _submodule_branch(vault_dir, raw_submodule_path)
    actions = [
        f"initialize configured raw submodule at {raw_submodule_path}",
        f"ensure raw submodule tracks {branch}",
    ]
    if dry_run:
        return actions, configured_origin

    _run(["git", "submodule", "sync", "--", raw_submodule_path], cwd=vault_dir)
    _run(["git", "submodule", "update", "--init", "--recursive", "--", raw_submodule_path], cwd=vault_dir)

    submodule_dir = os.path.join(vault_dir, raw_submodule_path)
    _run(["git", "fetch", "origin", branch], cwd=submodule_dir)

    current_head = _run_capture(["git", "rev-parse", "HEAD"], cwd=submodule_dir)
    current_branch = _run_capture(["git", "branch", "--show-current"], cwd=submodule_dir)
    branch_exists = _run_no_fail(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"], cwd=submodule_dir).returncode == 0

    if current_branch != branch:
        if not branch_exists:
            _run(["git", "branch", branch, current_head], cwd=submodule_dir)
            _run(["git", "checkout", branch], cwd=submodule_dir)
        else:
            branch_head = _run_capture(["git", "rev-parse", branch], cwd=submodule_dir)
            if branch_head == current_head:
                _run(["git", "checkout", branch], cwd=submodule_dir)
            else:
                actions.append(f"kept existing local {branch} branch tip unchanged")

    _run(["git", "branch", "--set-upstream-to", f"origin/{branch}", branch], cwd=submodule_dir)
    return actions, configured_origin


def _ensure_raw_submodule(
    vault_dir: str,
    *,
    raw_repo_url: str,
    raw_repo_slug: str,
    raw_submodule_path: str,
    dry_run: bool,
) -> str:
    abs_submodule = os.path.join(vault_dir, raw_submodule_path)
    if os.path.exists(abs_submodule) and not _submodule_matches(
        vault_dir,
        submodule_path=raw_submodule_path,
        repo_slug=raw_repo_slug,
    ):
        _die(
            "Raw submodule path already exists but is not the expected submodule:\n"
            f"  {abs_submodule}\n"
            "Clean the path or choose a different --raw-submodule-path."
        )

    if _submodule_matches(vault_dir, submodule_path=raw_submodule_path, repo_slug=raw_repo_slug):
        if not dry_run:
            _run(["git", "submodule", "update", "--init", "--recursive", "--", raw_submodule_path], cwd=vault_dir)
        return "reuse"

    if dry_run:
        return "add"

    _run(["git", "submodule", "add", raw_repo_url, raw_submodule_path], cwd=vault_dir)
    _run(["git", "submodule", "update", "--init", "--recursive", "--", raw_submodule_path], cwd=vault_dir)
    return "add"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Clone a confirmed Obsidian vault repo into ~/Documents and update obsidian-gh-knowledge config."
    )
    parser.add_argument(
        "--repo-url",
        required=True,
        help="Confirmed GitHub repo URL or owner/repo slug for the vault repo.",
    )
    parser.add_argument(
        "--vault-dir",
        default=None,
        help="Destination vault directory. Default: ~/Documents/<repo-name>",
    )
    parser.add_argument(
        "--vault-name",
        default=None,
        help="Optional Obsidian vault name to write to config when missing.",
    )
    parser.add_argument(
        "--repo-key",
        default=None,
        help="Optional repos.<key> alias to store in config.",
    )
    parser.add_argument(
        "--raw-submodule-url",
        default=None,
        help="Optional GitHub repo URL or owner/repo slug to mount as a raw-materials submodule.",
    )
    parser.add_argument(
        "--raw-submodule-path",
        default="raw",
        help='Vault-relative path for the raw-materials submodule. Default: "raw"',
    )
    parser.add_argument(
        "--init-raw-submodule",
        action="store_true",
        help="Initialize the raw-materials submodule after cloning or reusing the vault.",
    )
    parser.add_argument(
        "--force-default-repo",
        action="store_true",
        help="Overwrite config.default_repo with the confirmed repo.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print planned changes without cloning or writing config.")

    args = parser.parse_args()

    owner, repo = _parse_repo_url(args.repo_url)
    repo_slug = f"{owner}/{repo}"
    clone_url = _clone_url(owner, repo, args.repo_url.strip())
    vault_dir = _expand_path(args.vault_dir or f"~/Documents/{repo}")

    clone_action = _ensure_clone(clone_url, repo_slug, vault_dir, dry_run=args.dry_run)

    raw_action = None
    raw_repo_slug = None
    raw_repo_url = None
    raw_submodule_path = _relative_submodule_path(args.raw_submodule_path)
    if args.raw_submodule_url or args.init_raw_submodule:
        if not args.raw_submodule_url:
            _die("--init-raw-submodule requires --raw-submodule-url.")
        raw_owner, raw_repo = _parse_repo_url(args.raw_submodule_url)
        raw_repo_slug = f"{raw_owner}/{raw_repo}"
        raw_repo_url = _clone_url(raw_owner, raw_repo, args.raw_submodule_url.strip())
        raw_action = _ensure_raw_submodule(
            vault_dir,
            raw_repo_url=raw_repo_url,
            raw_repo_slug=raw_repo_slug,
            raw_submodule_path=raw_submodule_path,
            dry_run=args.dry_run,
        )

    git_bootstrap_actions = _bootstrap_repo_git(vault_dir, dry_run=args.dry_run)
    raw_bootstrap_actions, configured_raw_origin = _bootstrap_existing_raw_submodule(
        vault_dir,
        raw_submodule_path=raw_submodule_path,
        dry_run=args.dry_run,
    )
    if configured_raw_origin and not raw_repo_slug:
        raw_owner, raw_repo = _parse_repo_url(configured_raw_origin)
        raw_repo_slug = f"{raw_owner}/{raw_repo}"

    config = _load_config()
    config["local_vault_path"] = _display_path(vault_dir)
    config["prefer_local"] = True

    if args.force_default_repo or not isinstance(config.get("default_repo"), str) or not config.get("default_repo"):
        config["default_repo"] = repo_slug

    if args.repo_key:
        repos = config.get("repos")
        if not isinstance(repos, dict):
            repos = {}
        repos[args.repo_key] = repo_slug
        config["repos"] = repos

    if args.vault_name:
        config["vault_name"] = args.vault_name
    elif not isinstance(config.get("vault_name"), str) or not config.get("vault_name"):
        config["vault_name"] = os.path.basename(vault_dir)

    if raw_repo_slug:
        config["raw_submodule_path"] = raw_submodule_path
        config["raw_submodule_url"] = raw_repo_slug

    _write_config(config, dry_run=args.dry_run)

    print("Bootstrap plan complete.")
    print(f"Repo: {repo_slug}")
    print(f"Clone URL: {clone_url}")
    print(f"Vault directory: {vault_dir}")
    print(f"Config path: {CONFIG_PATH}")
    print(f"Clone action: {clone_action}")
    if raw_action:
        print(f"Raw submodule path: {raw_submodule_path}")
        print(f"Raw submodule repo: {raw_repo_slug}")
        print(f"Raw submodule action: {raw_action}")
    elif configured_raw_origin:
        print(f"Raw submodule path: {raw_submodule_path}")
        print(f"Raw submodule repo: {raw_repo_slug}")
        print("Raw submodule action: bootstrap existing config")
    if git_bootstrap_actions:
        print("Git bootstrap:")
        for action in git_bootstrap_actions:
            print(f"  - {action}")
    if raw_bootstrap_actions:
        print("Raw bootstrap:")
        for action in raw_bootstrap_actions:
            print(f"  - {action}")
    if args.dry_run:
        print("Dry run only. No files were changed.")
    else:
        print("Config updated with local_vault_path and prefer_local.")
    print("Next checks:")
    print(f"  cd {vault_dir}")
    print("  command -v obsidian")
    print("  obsidian help")


if __name__ == "__main__":
    main()
